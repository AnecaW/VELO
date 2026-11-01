begin;
-- Extend the existing private storage and queue; no second integration database.
alter table velo_private.connections add column generation uuid not null default gen_random_uuid(),
 add column refresh_lease_id uuid, add column sync_window jsonb not null default '{}',
 add column full_sync_at bigint not null default 0;
alter table velo_private.oauth_states add column connection_data jsonb;
alter table public.velo_jobs drop constraint velo_jobs_kind_check;
alter table public.velo_jobs add constraint velo_jobs_kind_check check(kind in ('sync','upload','webhook'));
alter table public.velo_jobs add column lease_token uuid, add column automatic boolean not null default false;
create index velo_strava_athlete on velo_private.connections((athlete->>'id'));

-- Keep established quota/cache operations behind the same service-only gateway.
alter function public.velo_private_call(text,jsonb) rename to velo_private_call_v240;
revoke all on function public.velo_private_call_v240(text,jsonb) from public,anon,authenticated,service_role;
create function public.velo_private_call(p_action text,p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; owner_id uuid:=(p_args->>'user_id')::uuid;
 t bigint:=extract(epoch from now())::bigint; o velo_private.oauth_states;
 c velo_private.connections; incoming jsonb; event_key text;
begin
 case p_action
 when 'oauth_create' then
  delete from velo_private.oauth_states where expires_at<t or user_id=owner_id;
  insert into velo_private.oauth_states(state_hash,user_id,state,challenge,expires_at)
   values(p_args->>'hash',owner_id,p_args->>'state',p_args->>'challenge',t+600);
 when 'oauth_stage' then
  update velo_private.oauth_states set connection_data=p_args->'connection',handoff_hash=p_args->>'handoff_hash'
   where state_hash=p_args->>'hash' and completed and expires_at>t
   returning jsonb_build_object('ok',true) into result;
 when 'oauth_confirm' then
  delete from velo_private.oauth_states where state_hash=p_args->>'hash' and user_id=owner_id
   and handoff_hash=p_args->>'handoff_hash' and expires_at>t and completed
   and challenge=p_args->>'challenge' and connection_data is not null returning * into o;
  if found then
   incoming:=o.connection_data;
   select * into c from velo_private.connections where user_id=owner_id for update;
   if c.user_id is not null and c.athlete->>'id' is distinct from incoming->'athlete'->>'id' then
    delete from velo_private.provider_cache where user_id=owner_id;
    update public.velo_jobs set status='failed',error='Strava-account gewijzigd. Kies de rit opnieuw.',lease_token=null
     where user_id=owner_id and status in ('pending','running');
   end if;
   insert into velo_private.connections(user_id,athlete,scope,token_cipher,expires_at)
    values(owner_id,incoming->'athlete',incoming->>'scope',incoming->>'token_cipher',(incoming->>'expires_at')::bigint)
    on conflict(user_id) do update set athlete=excluded.athlete,scope=excluded.scope,
     token_cipher=excluded.token_cipher,expires_at=excluded.expires_at,status='connected',error=null,
     generation=gen_random_uuid(),refresh_lease_id=null,refresh_lease_until=0,sync_window='{}',
     cursor=case when connections.athlete->>'id'=excluded.athlete->>'id' then connections.cursor else 0 end,
     full_sync_at=0;
   result:=jsonb_build_object('ok',true);
  end if;
 when 'token_lease' then
  update velo_private.connections set refresh_lease_until=t+60,refresh_lease_id=gen_random_uuid()
   where user_id=owner_id and status='connected' and refresh_lease_until<=t
   returning jsonb_build_object('ok',true,'lease',refresh_lease_id,'generation',generation) into result;
 when 'token_unlock' then
  update velo_private.connections set refresh_lease_until=0,refresh_lease_id=null
   where user_id=owner_id and refresh_lease_id::text=p_args->>'lease';
 when 'refresh_connection' then
  update velo_private.connections set token_cipher=p_args->>'token_cipher',expires_at=(p_args->>'expires_at')::bigint
   where user_id=owner_id and status='connected' and generation::text=p_args->>'generation'
   and refresh_lease_id::text=p_args->>'lease' and refresh_lease_until>t
   returning jsonb_build_object('ok',true) into result;
 when 'disconnect' then
  delete from velo_private.connections where user_id=owner_id;
  delete from velo_private.provider_cache where user_id=owner_id;
  delete from velo_private.oauth_states where user_id=owner_id;
  delete from public.velo_sync_history where user_id=owner_id;
  delete from public.velo_jobs where user_id=owner_id and kind<>'upload';
  update public.velo_jobs set status=case when status='complete' then 'complete' else 'needs_review' end,
   error=case when status='complete' then null else 'Strava is ontkoppeld. Controleer de vorige upload voordat je opnieuw probeert.' end,
   result=jsonb_build_object('external_id',velo_jobs.result->'external_id','previously_submitted',true),lease_token=null,lease_until=0
   where user_id=owner_id and kind='upload';
 when 'reconnect' then
  update velo_private.connections set status='needs_reconnect',error='Verbind Strava opnieuw.',token_cipher='',expires_at=0,
   refresh_lease_id=null,refresh_lease_until=0,generation=gen_random_uuid(),sync_window='{}' where user_id=owner_id;
  delete from velo_private.provider_cache where user_id=owner_id;
  update public.velo_jobs set status='failed',error='Verbind Strava opnieuw.',lease_token=null
   where user_id=owner_id and status in ('pending','running');
 when 'sync_window' then
  update velo_private.connections set sync_window=p_args->'window' where user_id=owner_id
   and generation::text=p_args->>'generation' and status='connected'
   returning jsonb_build_object('ok',true) into result;
 when 'sync_complete' then
  update velo_private.connections set cursor=greatest(cursor,(p_args->>'cursor')::bigint),last_sync=t,error=null,sync_window='{}',
   full_sync_at=case when p_args->>'full'='true' then t else full_sync_at end,
   preferences=jsonb_set(preferences,'{route_page}',coalesce(p_args->'route_page','1'::jsonb),true)
   where user_id=owner_id and generation::text=p_args->>'generation' and status='connected'
   returning jsonb_build_object('ok',true) into result;
 when 'save_cache' then
  if exists(select 1 from velo_private.connections where user_id=owner_id and status='connected'
   and generation::text=p_args->>'generation') then
   insert into velo_private.provider_cache values(owner_id,p_args->>'kind',p_args->>'id',p_args->'data',t+86400)
    on conflict(user_id,kind,id) do update set data=excluded.data,expires_at=excluded.expires_at;
  end if;
 when 'remove_cached_activity' then
  delete from velo_private.provider_cache where user_id=owner_id and kind='activities' and id=p_args->>'id';
 when 'cache_page' then
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('data',x.data)),'[]'),
   'total',(select count(*) from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t)) into result
   from (select data from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t
    order by coalesce(data->>'start_date','') desc,id desc limit least(100,(p_args->>'limit')::int)
    offset greatest(0,(p_args->>'offset')::int)) x;
 when 'cache_counts' then
  select jsonb_build_object('activities',count(*) filter(where kind='activities'),'routes',count(*) filter(where kind='routes'))
   into result from velo_private.provider_cache where user_id=owner_id and expires_at>t;
 when 'webhook_receive' then
  incoming:=p_args->'event';
  for c in select * from velo_private.connections where athlete->>'id'=incoming->>'owner_id' and status='connected' loop
   event_key:='event-'||(p_args->>'hash');
   insert into public.velo_jobs(user_id,kind,job_key,result)
    values(c.user_id,'webhook',event_key,jsonb_build_object('event',incoming,'generation',c.generation))
    on conflict(user_id,kind,job_key) do nothing;
  end loop;
 when 'claim_job' then
  update public.velo_jobs set status='running',attempts=attempts+1,lease_until=t+120,lease_token=gen_random_uuid()
   where id=(select id from public.velo_jobs where status='pending' and next_at<=t
    and (owner_id is null or user_id=owner_id) and not exists(select 1 from public.velo_jobs busy
     where busy.user_id=velo_jobs.user_id and busy.status='running') order by next_at for update skip locked limit 1)
   returning to_jsonb(velo_jobs) into result;
 when 'maintenance' then
  delete from velo_private.provider_cache where expires_at<t;
  delete from velo_private.oauth_states where expires_at<t;
  delete from velo_private.rate_limits where until_at<t;
  delete from public.velo_sync_history where created_at<t-2592000;
  update public.velo_jobs set status=case when kind='upload' and velo_jobs.result->>'upload_intent'='true' and velo_jobs.result->>'upload_id' is null
    then 'needs_review' else 'pending' end,error='Vorige verwerking onderbroken.',lease_token=null
   where status='running' and lease_until<t;
  delete from public.velo_jobs where kind in ('sync','webhook') and status in ('complete','skipped') and next_at<t-2592000;
  insert into public.velo_jobs(user_id,kind,job_key)
   select user_id,'sync','automatic-'||(t/21600)::text from velo_private.connections
   where status='connected' and preferences->>'automatic'='true' and preferences->>'enabled'='true'
    and coalesce(last_sync,0)<t-21600 and not exists(select 1 from public.velo_jobs j
     where j.user_id=connections.user_id and j.kind='sync' and j.status in ('pending','running'))
   on conflict do nothing;
 else return public.velo_private_call_v240(p_action,p_args);
 end case;
 return result;
end $$;
revoke all on function public.velo_private_call(text,jsonb) from public,anon,authenticated;
grant execute on function public.velo_private_call(text,jsonb) to service_role;
commit;

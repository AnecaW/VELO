begin;
alter table velo_private.connections add column refresh_lease_until bigint not null default 0;
create or replace function public.velo_private_call(p_action text,p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; owner_id uuid:=(p_args->>'user_id')::uuid; t bigint:=extract(epoch from now())::bigint;
begin
 case p_action
 when 'connection' then select to_jsonb(c) into result from velo_private.connections c where user_id=owner_id;
 when 'save_connection' then
   if not exists(select 1 from velo_private.oauth_states where state_hash=p_args->>'oauth_hash' and user_id=owner_id and completed=true and expires_at>t) then raise exception 'oauth_session_ended'; end if;
   insert into velo_private.connections(user_id,athlete,scope,token_cipher,expires_at) values(owner_id,p_args->'athlete',p_args->>'scope',p_args->>'token_cipher',(p_args->>'expires_at')::bigint)
   on conflict(user_id) do update set athlete=excluded.athlete,scope=excluded.scope,token_cipher=excluded.token_cipher,expires_at=excluded.expires_at,status='connected',error=null;
 when 'token_lease' then
   update velo_private.connections set refresh_lease_until=t+60 where user_id=owner_id and status='connected' and refresh_lease_until<=t returning jsonb_build_object('ok',true) into result;
 when 'token_unlock' then update velo_private.connections set refresh_lease_until=0 where user_id=owner_id;
 when 'refresh_connection' then
   update velo_private.connections set token_cipher=p_args->>'token_cipher',expires_at=(p_args->>'expires_at')::bigint where user_id=owner_id and status='connected' returning jsonb_build_object('ok',true) into result;
 when 'strava_allowed' then
   select jsonb_build_object('until',until_at) into result from velo_private.rate_limits where key='strava:block' and until_at>t;
 when 'strava_block' then
   insert into velo_private.rate_limits values('strava:block',1,(p_args->>'until')::bigint)
   on conflict(key) do update set until_at=greatest(rate_limits.until_at,excluded.until_at);
 when 'preferences' then update velo_private.connections set preferences=p_args->'preferences' where user_id=owner_id;
 when 'sync_complete' then update velo_private.connections set cursor=greatest(cursor,(p_args->>'cursor')::bigint),last_sync=t,error=null,preferences=jsonb_set(preferences,'{route_page}',coalesce(p_args->'route_page','1'::jsonb),true) where user_id=owner_id;
 when 'reconnect' then update velo_private.connections set status='needs_reconnect',error='Verbind Strava opnieuw.' where user_id=owner_id;
 when 'disconnect' then
   delete from velo_private.connections where user_id=owner_id;
   delete from velo_private.provider_cache where user_id=owner_id;
   delete from velo_private.oauth_states where user_id=owner_id;
   delete from public.velo_jobs where user_id=owner_id;
 when 'reset_cache' then delete from velo_private.provider_cache where user_id=owner_id;update velo_private.connections set cursor=0 where user_id=owner_id;
 when 'oauth_create' then
   delete from velo_private.oauth_states where expires_at<t;
   insert into velo_private.oauth_states values(p_args->>'hash',owner_id,p_args->>'state',p_args->>'challenge',null,t+600,false);
 when 'oauth_get' then select to_jsonb(s) into result from velo_private.oauth_states s where state_hash=p_args->>'hash' and expires_at>t;
 when 'oauth_lock' then
   update velo_private.oauth_states set completed=true where state_hash=p_args->>'hash' and expires_at>t and completed=false returning to_jsonb(oauth_states) into result;
 when 'oauth_handoff' then update velo_private.oauth_states set handoff_hash=p_args->>'handoff_hash' where state_hash=p_args->>'hash' and completed=true;
 when 'oauth_confirm' then
   delete from velo_private.oauth_states where state_hash=p_args->>'hash' and user_id=owner_id and handoff_hash=p_args->>'handoff_hash' and expires_at>t and challenge=p_args->>'challenge' returning jsonb_build_object('ok',true) into result;
 when 'cache' then
   select coalesce(jsonb_agg(jsonb_build_object('data',data)),'[]') into result from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t;
 when 'save_cache' then
   insert into velo_private.provider_cache values(owner_id,p_args->>'kind',p_args->>'id',p_args->'data',t+86400)
   on conflict(user_id,kind,id) do update set data=excluded.data,expires_at=excluded.expires_at;
 when 'claim_job' then
   update public.velo_jobs set status='running',attempts=attempts+1,lease_until=t+120
   where id=(select id from public.velo_jobs where status='pending' and next_at<=t and (owner_id is null or user_id=owner_id) and not exists(select 1 from public.velo_jobs busy where busy.user_id=velo_jobs.user_id and busy.status='running') order by next_at for update skip locked limit 1)
   returning to_jsonb(velo_jobs) into result;
 when 'maintenance' then
   delete from velo_private.provider_cache where expires_at<t;
   delete from velo_private.oauth_states where expires_at<t;
   delete from velo_private.rate_limits where until_at<t;
   delete from public.velo_sync_history where created_at<t-2592000;
   update public.velo_jobs set status=case when kind='upload' then 'needs_review' else 'pending' end,error='Vorige verwerking onderbroken.' where status='running' and lease_until<t;
   insert into public.velo_jobs(user_id,kind,job_key)
     select user_id,'sync','automatic-'||(t/900)::text from velo_private.connections
     where status='connected' and preferences->>'automatic'='true' and preferences->>'enabled'='true' and coalesce(last_sync,0)<t-900
     and not exists(select 1 from public.velo_jobs j where j.user_id=connections.user_id and j.kind='sync' and j.status in ('pending','running'))
     on conflict do nothing;
 when 'rate_limit' then
   insert into velo_private.rate_limits values(p_args->>'key',1,t+(p_args->>'window')::bigint)
   on conflict(key) do update set count=case when rate_limits.until_at<t then 1 else rate_limits.count+1 end,until_at=case when rate_limits.until_at<t then excluded.until_at else rate_limits.until_at end
   returning jsonb_build_object('allowed',count<=(p_args->>'limit')::int) into result;
 else raise exception 'unknown operation';
 end case;
 return result;
end $$;
commit;

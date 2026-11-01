begin;
create or replace function public.velo_write_document(p_kind text,p_id text,p_payload jsonb,p_expected_revision bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); old public.velo_documents; new_revision bigint; size_bytes bigint;
begin
  if owner_id is null then raise insufficient_privilege; end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
  select * into old from public.velo_documents where user_id=owner_id and kind=p_kind and id=p_id for update;
  if found then
    if old.payload is not distinct from p_payload then return jsonb_build_object('revision',old.revision); end if;
    if p_expected_revision is distinct from old.revision then
      raise exception 'revision_conflict' using errcode='PT409';
    end if;
  elsif p_expected_revision is not null then raise exception 'revision_conflict' using errcode='PT409';
  end if;
  select coalesce(sum(octet_length(payload::text)),0) into size_bytes from public.velo_documents where user_id=owner_id;
  if size_bytes - coalesce(octet_length(old.payload::text),0) + coalesce(octet_length(p_payload::text),0) > 209715200 then
    raise exception 'account_storage_limit' using errcode='54000';
  end if;
  if p_payload is not null and p_kind='rides' and (p_payload->>'id' is distinct from p_id or p_payload->>'v' is distinct from '1' or jsonb_typeof(p_payload->'points') is distinct from 'array') then
    raise exception 'invalid_ride' using errcode='22023';
  end if;
  if old.user_id is null and (select count(*) from public.velo_documents where user_id=owner_id)>=20000 then
    raise exception 'account_document_limit' using errcode='54000';
  end if;
  new_revision:=nextval('public.velo_revision_seq');
  insert into public.velo_documents(user_id,kind,id,payload,deleted,revision)
    values(owner_id,p_kind,p_id,p_payload,p_payload is null,new_revision)
  on conflict(user_id,kind,id) do update set payload=excluded.payload,deleted=excluded.deleted,revision=excluded.revision,updated_at=now();
  return jsonb_build_object('revision',new_revision);
end $$;
create or replace function public.velo_private_call(p_action text,p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; owner_id uuid:=(p_args->>'user_id')::uuid; t bigint:=extract(epoch from now())::bigint;
begin
 case p_action
 when 'connection' then select to_jsonb(c) into result from velo_private.connections c where user_id=owner_id;
 when 'save_connection' then
   insert into velo_private.connections(user_id,athlete,scope,token_cipher,expires_at) values(owner_id,p_args->'athlete',p_args->>'scope',p_args->>'token_cipher',(p_args->>'expires_at')::bigint)
   on conflict(user_id) do update set athlete=excluded.athlete,scope=excluded.scope,token_cipher=excluded.token_cipher,expires_at=excluded.expires_at,status='connected',error=null;
 when 'refresh_connection' then
   update velo_private.connections set token_cipher=p_args->>'token_cipher',expires_at=(p_args->>'expires_at')::bigint where user_id=owner_id and status='connected' returning jsonb_build_object('ok',true) into result;
 when 'strava_allowed' then
   select jsonb_build_object('until',until_at) into result from velo_private.rate_limits where key='strava:block' and until_at>t;
 when 'strava_block' then
   insert into velo_private.rate_limits values('strava:block',1,(p_args->>'until')::bigint)
   on conflict(key) do update set until_at=greatest(rate_limits.until_at,excluded.until_at);
 when 'preferences' then update velo_private.connections set preferences=p_args->'preferences' where user_id=owner_id;
 when 'sync_complete' then update velo_private.connections set cursor=greatest(cursor,(p_args->>'cursor')::bigint),last_sync=t,error=null where user_id=owner_id;
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

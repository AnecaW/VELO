-- Account data remains compatible with the app's lossless offline document format.
begin;
create schema if not exists velo_private;
revoke all on schema velo_private from public, anon, authenticated;
grant usage on schema velo_private to service_role;
create sequence if not exists public.velo_revision_seq;
revoke all on sequence public.velo_revision_seq from public, anon, authenticated;

create table public.velo_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (length(display_name) <= 100),
  created_at timestamptz not null default now()
);
alter table public.velo_profiles enable row level security;
create policy own_profile_read on public.velo_profiles for select to authenticated using ((select auth.uid())=user_id);
create policy own_profile_insert on public.velo_profiles for insert to authenticated with check ((select auth.uid())=user_id);
create policy own_profile_update on public.velo_profiles for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
revoke all on public.velo_profiles from anon, authenticated;
grant select,insert,update on public.velo_profiles to authenticated;

create table public.velo_documents (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('rides','routes','settings','profiles','training_plans','training_profile','training_results')),
  id text not null check(length(id) between 1 and 512 and id !~ '[[:cntrl:]]' and id not like 'strava:%'),
  payload jsonb,
  deleted boolean not null default false,
  revision bigint not null default nextval('public.velo_revision_seq'),
  updated_at timestamptz not null default now(),
  primary key(user_id,kind,id),
  check(deleted = (payload is null)),
  check(payload is null or (jsonb_typeof(payload)='object' and octet_length(payload::text)<=10485760 and coalesce(payload->>'source','')<>'Strava'))
);
create index velo_documents_cursor on public.velo_documents(user_id,kind,revision);
alter table public.velo_documents enable row level security;
create policy own_documents_read on public.velo_documents for select to authenticated using ((select auth.uid())=user_id);
revoke all on public.velo_documents from anon, authenticated;
grant select on public.velo_documents to authenticated;
grant all on public.velo_documents, public.velo_profiles to service_role;
grant all on sequence public.velo_revision_seq to service_role;

create function public.velo_documents_page(p_kind text,p_after bigint default 0) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare items jsonb; next_cursor bigint; more boolean;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select coalesce(jsonb_agg(to_jsonb(d) - 'user_id' order by revision),'[]'::jsonb),coalesce(max(revision),p_after)
  into items,next_cursor from (
    select id,payload,deleted,revision,extract(epoch from updated_at)::bigint as updated_at
    from public.velo_documents where user_id=auth.uid() and kind=p_kind and revision>p_after order by revision limit 100
  ) d;
  select exists(select 1 from public.velo_documents where user_id=auth.uid() and kind=p_kind and revision>next_cursor) into more;
  return jsonb_build_object('items',items,'cursor',next_cursor,'has_more',more);
end $$;

-- No client-supplied user ID. All writes are serialized per authenticated owner.
create function public.velo_write_document(p_kind text,p_id text,p_payload jsonb,p_expected_revision bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); old public.velo_documents; new_revision bigint; size_bytes bigint;
begin
  if owner_id is null then raise insufficient_privilege; end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
  select * into old from public.velo_documents where user_id=owner_id and kind=p_kind and id=p_id for update;
  if found then
    if old.payload is not distinct from p_payload then return jsonb_build_object('revision',old.revision); end if;
    if p_expected_revision is distinct from old.revision then
      raise exception 'revision_conflict' using errcode='40001';
    end if;
  elsif p_expected_revision is not null then raise exception 'revision_conflict' using errcode='40001';
  end if;
  select coalesce(sum(octet_length(payload::text)),0) into size_bytes from public.velo_documents where user_id=owner_id;
  if size_bytes - coalesce(octet_length(old.payload::text),0) + coalesce(octet_length(p_payload::text),0) > 209715200 then
    raise exception 'account_storage_limit' using errcode='54000';
  end if;
  new_revision:=nextval('public.velo_revision_seq');
  insert into public.velo_documents(user_id,kind,id,payload,deleted,revision)
    values(owner_id,p_kind,p_id,p_payload,p_payload is null,new_revision)
  on conflict(user_id,kind,id) do update set payload=excluded.payload,deleted=excluded.deleted,revision=excluded.revision,updated_at=now();
  return jsonb_build_object('revision',new_revision);
end $$;
revoke all on function public.velo_documents_page(text,bigint),public.velo_write_document(text,text,jsonb,bigint) from public, anon;
grant execute on function public.velo_documents_page(text,bigint),public.velo_write_document(text,text,jsonb,bigint) to authenticated;

-- Private tables never appear in the public Data API. No user JWT can read tokens.
create table velo_private.connections (
 user_id uuid primary key references auth.users(id) on delete cascade,
 provider text not null default 'strava', athlete jsonb not null default '{}', scope text not null,
 token_cipher text not null, expires_at bigint not null,
 status text not null default 'connected', preferences jsonb not null default '{"enabled":true,"automatic":false,"activities":true,"routes":false,"uploads":false}',
 cursor bigint not null default 0,last_sync bigint,error text
);
create table velo_private.oauth_states (
 state_hash text primary key,user_id uuid not null references auth.users(id) on delete cascade,
 state text not null,challenge text not null,handoff_hash text,expires_at bigint not null,completed boolean not null default false
);
create table public.velo_jobs (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('sync','upload')),job_key text not null,status text not null default 'pending',
 attempts integer not null default 0,next_at bigint not null default extract(epoch from now())::bigint,
 lease_until bigint not null default 0,result jsonb,error text,
 unique(user_id,kind,job_key)
);
create table public.velo_sync_history (
 id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,
 provider text not null default 'strava',status text not null,message text,
 created_at bigint not null default extract(epoch from now())::bigint
);
create table velo_private.provider_cache (
 user_id uuid not null references auth.users(id) on delete cascade,kind text not null,id text not null,data jsonb not null,
 expires_at bigint not null, primary key(user_id,kind,id)
);
create table velo_private.rate_limits (key text primary key,count integer not null,until_at bigint not null);
alter table velo_private.connections enable row level security;
alter table velo_private.oauth_states enable row level security;
alter table velo_private.provider_cache enable row level security;
alter table velo_private.rate_limits enable row level security;
alter table public.velo_jobs enable row level security;
alter table public.velo_sync_history enable row level security;
create policy own_jobs_read on public.velo_jobs for select to authenticated using ((select auth.uid())=user_id);
create policy own_history_read on public.velo_sync_history for select to authenticated using ((select auth.uid())=user_id);
revoke all on public.velo_jobs,public.velo_sync_history from anon,authenticated;
grant select on public.velo_jobs,public.velo_sync_history to authenticated;
grant all on all tables in schema velo_private to service_role;
grant all on public.velo_jobs,public.velo_sync_history to service_role;
grant usage,select on all sequences in schema public to service_role;

-- Service-only RPCs expose narrowly scoped operations instead of exposing a private schema.
create function public.velo_private_call(p_action text,p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; owner_id uuid:=(p_args->>'user_id')::uuid; t bigint:=extract(epoch from now())::bigint;
begin
 case p_action
 when 'connection' then select to_jsonb(c) into result from velo_private.connections c where user_id=owner_id;
 when 'save_connection' then
   insert into velo_private.connections(user_id,athlete,scope,token_cipher,expires_at) values(owner_id,p_args->'athlete',p_args->>'scope',p_args->>'token_cipher',(p_args->>'expires_at')::bigint)
   on conflict(user_id) do update set athlete=excluded.athlete,scope=excluded.scope,token_cipher=excluded.token_cipher,expires_at=excluded.expires_at,status='connected',error=null;
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
   where id=(select id from public.velo_jobs where status='pending' and next_at<=t and (owner_id is null or user_id=owner_id) order by next_at for update skip locked limit 1)
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
revoke all on function public.velo_private_call(text,jsonb) from public,anon,authenticated;
grant execute on function public.velo_private_call(text,jsonb) to service_role;
commit;

begin;
alter table public.velo_jobs add column updated_at timestamptz not null default now();
create function velo_private.touch_strava_job() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at:=now(); return new; end $$;
revoke all on function velo_private.touch_strava_job() from public,anon,authenticated;
create trigger velo_job_updated before update on public.velo_jobs for each row execute function velo_private.touch_strava_job();
alter function public.velo_private_call(text,jsonb) rename to velo_private_call_v250;
revoke all on function public.velo_private_call_v250(text,jsonb) from public,anon,authenticated,service_role;
create function public.velo_private_call(p_action text,p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; owner_id uuid:=(p_args->>'user_id')::uuid; t bigint:=extract(epoch from now())::bigint;
begin
 if p_action='cache_page' then
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('data',x.data,'expires_at',x.expires_at)),'[]'),
   'total',(select count(*) from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t)) into result
   from (select data,expires_at from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t
    order by coalesce(data->>'start_date','') desc,id desc limit least(100,(p_args->>'limit')::int)
    offset greatest(0,(p_args->>'offset')::int)) x;
 elsif p_action='cache' then
  select coalesce(jsonb_agg(jsonb_build_object('data',data,'expires_at',expires_at)),'[]') into result
   from velo_private.provider_cache where user_id=owner_id and kind=p_args->>'kind' and expires_at>t;
 elsif p_action='reset_cache' then
  delete from velo_private.provider_cache where user_id=owner_id;
  update velo_private.connections set cursor=0,full_sync_at=0,sync_window='{}' where user_id=owner_id;
 else return public.velo_private_call_v250(p_action,p_args);
 end if;
 return result;
end $$;
revoke all on function public.velo_private_call(text,jsonb) from public,anon,authenticated;
grant execute on function public.velo_private_call(text,jsonb) to service_role;
commit;

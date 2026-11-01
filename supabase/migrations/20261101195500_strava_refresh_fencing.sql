begin;
create function public.velo_strava_reconnect(p_user_id uuid,p_generation uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 update velo_private.connections set status='needs_reconnect',error='Verbind Strava opnieuw.',token_cipher='',expires_at=0,
  refresh_lease_id=null,refresh_lease_until=0,generation=gen_random_uuid(),sync_window='{}'
  where user_id=p_user_id and generation=p_generation;
 if not found then return false; end if;
 delete from velo_private.provider_cache where user_id=p_user_id;
 update public.velo_jobs set status='failed',error='Verbind Strava opnieuw.',lease_token=null where user_id=p_user_id and status in ('pending','running');
 return true;
end $$;
revoke all on function public.velo_strava_reconnect(uuid,uuid) from public,anon,authenticated;
grant execute on function public.velo_strava_reconnect(uuid,uuid) to service_role;
commit;

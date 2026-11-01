begin;
create function velo_private.purge_strava_data(p_owner uuid) returns void language plpgsql set search_path='' as $$
begin
 delete from velo_private.provider_cache where user_id=p_owner;
 delete from velo_private.oauth_states where user_id=p_owner;
 delete from public.velo_sync_history where user_id=p_owner;
 delete from public.velo_jobs where user_id=p_owner and kind<>'upload';
 update public.velo_jobs set status=case when status='complete' or result->>'removed'='true' then 'complete' else 'needs_review' end,
  error=case when status='complete' or result->>'removed'='true' then null else 'Vorige Strava-koppeling beëindigd. Controleer eerst of de rit al verstuurd is.' end,
  result=jsonb_build_object('external_id',result->'external_id','removed',coalesce(result->'removed','false'::jsonb),'previously_submitted',true),
  lease_token=null,lease_until=0 where user_id=p_owner and kind='upload';
end $$;
revoke all on function velo_private.purge_strava_data(uuid) from public,anon,authenticated,service_role;
create function public.velo_strava_disconnect(p_user_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from velo_private.connections where user_id=p_user_id;
 perform velo_private.purge_strava_data(p_user_id);
end $$;
revoke all on function public.velo_strava_disconnect(uuid) from public,anon,authenticated;
grant execute on function public.velo_strava_disconnect(uuid) to service_role;
create or replace function public.velo_strava_reconnect(p_user_id uuid,p_generation uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 update velo_private.connections set status='needs_reconnect',error='Verbind Strava opnieuw.',token_cipher='',expires_at=0,athlete='{}',scope='',
  refresh_lease_id=null,refresh_lease_until=0,generation=gen_random_uuid(),sync_window='{}',cursor=0,last_sync=null,full_sync_at=0
  where user_id=p_user_id and generation=p_generation;
 if not found then return false; end if;
 perform velo_private.purge_strava_data(p_user_id);
 return true;
end $$;
commit;

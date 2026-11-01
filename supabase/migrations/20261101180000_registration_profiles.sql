begin;
create function velo_private.create_registration_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into public.velo_profiles(user_id,display_name)
  values(new.id,left(trim(coalesce(new.raw_user_meta_data->>'display_name','')),80))
  on conflict(user_id) do nothing;
  return new;
end $$;
revoke all on function velo_private.create_registration_profile() from public,anon,authenticated;
create trigger velo_registration_profile after insert on auth.users
for each row execute function velo_private.create_registration_profile();
commit;

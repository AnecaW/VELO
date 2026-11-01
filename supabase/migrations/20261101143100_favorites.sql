begin;
alter table public.velo_documents drop constraint velo_documents_kind_check;
alter table public.velo_documents add constraint velo_documents_kind_check check(kind in ('rides','routes','settings','profiles','training_plans','training_profile','training_results','sensor_configs','favorites'));
create view public.velo_favorite_places with(security_invoker=true) as select user_id,id,payload from public.velo_documents where kind='favorites' and not deleted;
revoke all on public.velo_favorite_places from anon,authenticated;
grant select on public.velo_favorite_places to authenticated,service_role;
commit;

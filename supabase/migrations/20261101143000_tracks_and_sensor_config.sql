begin;
alter table public.velo_documents drop constraint velo_documents_kind_check;
alter table public.velo_documents add constraint velo_documents_kind_check check(kind in ('rides','routes','settings','profiles','training_plans','training_profile','training_results','sensor_configs'));

-- Track geometry is not fetched by ordinary activity/statistics queries.
create table public.velo_tracks (
 user_id uuid not null,
 kind text not null default 'rides' check(kind='rides'),
 ride_id text not null,
 points jsonb not null check(jsonb_typeof(points)='array' and octet_length(points::text)<=10485760),
 primary key(user_id,ride_id),
 foreign key(user_id,kind,ride_id) references public.velo_documents(user_id,kind,id) on delete cascade
);
alter table public.velo_tracks enable row level security;
create policy own_track_read on public.velo_tracks for select to authenticated using((select auth.uid())=user_id);
revoke all on public.velo_tracks from anon,authenticated;
grant select on public.velo_tracks to authenticated;
grant all on public.velo_tracks to service_role;
insert into public.velo_tracks(user_id,ride_id,points) select user_id,id,payload->'points' from public.velo_documents where kind='rides' and deleted=false and jsonb_typeof(payload->'points')='array';
update public.velo_documents set payload=payload-'points' where kind='rides' and deleted=false;

create or replace function public.velo_documents_page(p_kind text,p_after bigint default 0) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare items jsonb; next_cursor bigint; more boolean;
begin
 if auth.uid() is null then raise insufficient_privilege; end if;
 select coalesce(jsonb_agg(to_jsonb(d)-'user_id' order by revision),'[]'::jsonb),coalesce(max(revision),p_after)
 into items,next_cursor from (
   select a.id,case when a.kind='rides' and not a.deleted then a.payload||jsonb_build_object('points',coalesce(t.points,'[]'::jsonb)) else a.payload end payload,
     a.deleted,a.revision,extract(epoch from a.updated_at)::bigint updated_at
   from public.velo_documents a left join public.velo_tracks t on a.kind='rides' and t.user_id=a.user_id and t.ride_id=a.id
   where a.user_id=auth.uid() and a.kind=p_kind and a.revision>p_after order by a.revision limit case when p_kind='rides' then 1 else 100 end
 ) d;
 select exists(select 1 from public.velo_documents where user_id=auth.uid() and kind=p_kind and revision>next_cursor) into more;
 return jsonb_build_object('items',items,'cursor',next_cursor,'has_more',more);
end $$;

create or replace function public.velo_write_document(p_kind text,p_id text,p_payload jsonb,p_expected_revision bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); old public.velo_documents; full_old jsonb; new_revision bigint; size_bytes bigint; old_size bigint;
begin
 if owner_id is null then raise insufficient_privilege; end if;
 if p_payload is not null and (jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>10485760) then raise exception 'invalid_document' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
 select * into old from public.velo_documents where user_id=owner_id and kind=p_kind and id=p_id for update;
 if found then
   full_old:=old.payload;
   if p_kind='rides' and not old.deleted then
     select old.payload||jsonb_build_object('points',points) into full_old from public.velo_tracks where user_id=owner_id and ride_id=p_id;
   end if;
   if full_old is not distinct from p_payload then return jsonb_build_object('revision',old.revision); end if;
   if p_expected_revision is distinct from old.revision then raise exception 'revision_conflict' using errcode='PT409'; end if;
 elsif p_expected_revision is not null then raise exception 'revision_conflict' using errcode='PT409';
 end if;
 if p_payload is not null and p_kind='rides' then
   if p_payload->>'id' is distinct from p_id or p_payload->>'v' is distinct from '1' or jsonb_typeof(p_payload->'points') is distinct from 'array' then raise exception 'invalid_ride' using errcode='22023'; end if;
 end if;
 if old.user_id is null and (select count(*) from public.velo_documents where user_id=owner_id)>=20000 then raise exception 'account_document_limit' using errcode='54000'; end if;
 select coalesce(sum(octet_length(payload::text)),0) into size_bytes from public.velo_documents where user_id=owner_id;
 select size_bytes+coalesce(sum(octet_length(points::text)),0) into size_bytes from public.velo_tracks where user_id=owner_id;
 old_size:=coalesce(octet_length(full_old::text),0);
 if size_bytes-old_size+coalesce(octet_length(p_payload::text),0)>209715200 then raise exception 'account_storage_limit' using errcode='54000'; end if;
 new_revision:=nextval('public.velo_revision_seq');
 insert into public.velo_documents(user_id,kind,id,payload,deleted,revision)
   values(owner_id,p_kind,p_id,case when p_kind='rides' then p_payload-'points' else p_payload end,p_payload is null,new_revision)
 on conflict(user_id,kind,id) do update set payload=excluded.payload,deleted=excluded.deleted,revision=excluded.revision,updated_at=now();
 if p_kind='rides' then
   if p_payload is null then delete from public.velo_tracks where user_id=owner_id and ride_id=p_id;
   else insert into public.velo_tracks(user_id,ride_id,points) values(owner_id,p_id,p_payload->'points') on conflict(user_id,ride_id) do update set points=excluded.points;
   end if;
 end if;
 return jsonb_build_object('revision',new_revision);
end $$;

-- Readable, lightweight domain projections. Security-invoker retains underlying RLS.
create view public.velo_activities with(security_invoker=true) as
 select user_id,id,payload,revision,updated_at from public.velo_documents where kind='rides' and not deleted;
create view public.velo_routes with(security_invoker=true) as
 select user_id,id,payload,revision,updated_at from public.velo_documents where kind='routes' and not deleted;
create view public.velo_training_plans with(security_invoker=true) as
 select user_id,id,payload,revision,updated_at from public.velo_documents where kind='training_plans' and not deleted;
create view public.velo_sensor_configs with(security_invoker=true) as
 select user_id,id,payload,revision,updated_at from public.velo_documents where kind='sensor_configs' and not deleted;
create view public.velo_favorites with(security_invoker=true) as
 select user_id,payload->'favoriteApps' apps,payload->'favoritesOnly' favorites_only from public.velo_documents where kind='settings' and id='app' and not deleted;
revoke all on public.velo_activities,public.velo_routes,public.velo_training_plans,public.velo_sensor_configs,public.velo_favorites from anon,authenticated;
grant select on public.velo_activities,public.velo_routes,public.velo_training_plans,public.velo_sensor_configs,public.velo_favorites to authenticated,service_role;
commit;

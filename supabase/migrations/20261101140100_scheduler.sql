begin;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
-- Secret generated in PostgreSQL; the checked-in migration contains no credential.
do $$ begin
  if not exists(select 1 from vault.secrets where name='velo_scheduler_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'velo_scheduler_token','VELO scheduled Edge worker');
  end if;
end $$;
-- Only postgres schedules it. The command resolves the secret from Vault at runtime.
select cron.schedule('velo-sync-worker','* * * * *', $job$
  select net.http_post(
    url:='https://pdooxhljbutbsotbjbrt.supabase.co/functions/v1/velo-worker',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='velo_scheduler_token')),
    body:='{}'::jsonb,timeout_milliseconds:=10000
  );
$job$);
commit;

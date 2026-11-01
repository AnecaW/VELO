begin;
create index velo_pending_jobs on public.velo_jobs(next_at) where status='pending';
create index velo_running_jobs on public.velo_jobs(lease_until) where status='running';
create index velo_owner_history on public.velo_sync_history(user_id,created_at desc);
create index velo_cache_expiry on velo_private.provider_cache(expires_at);
create index velo_oauth_expiry on velo_private.oauth_states(expires_at);
create index velo_quota_expiry on velo_private.rate_limits(until_at);
commit;

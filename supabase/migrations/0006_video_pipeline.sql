-- ============================================================================
-- 0006_video_pipeline.sql
-- Phase C (Video). Support for the upload/processing webhook: idempotency
-- log (section 43) and a lookup index. The columns the webhook writes to
-- (video_provider, video_asset_id, playback_id, thumbnail_url, duration_ms,
-- status, published_at) already exist on `ads` from 0005 — this migration
-- only adds what's new for the pipeline itself.
-- ============================================================================

-- Every processed provider webhook event is recorded here by its provider
-- event id, so a retried delivery (providers retry on any non-2xx, or on
-- timeout even after a successful write) is a no-op the second time
-- (CLAUDE.md section 43: "Ensure webhook handling is idempotent").
create table public.video_webhook_events (
  provider text not null,
  event_id text not null,
  received_at timestamptz not null default now(),

  primary key (provider, event_id)
);

comment on table public.video_webhook_events is
  'Idempotency log for video-provider webhooks. Insert-before-process; a primary key conflict means "already handled".';

-- The webhook looks up an Ad by the provider's asset id once an asset
-- exists (video.asset.created/ready); primary correlation is via Mux
-- `passthrough` = ads.id, but this index keeps the fallback lookup path
-- (video.asset.errored, video.asset.deleted arriving without passthrough
-- in some provider configurations) fast instead of a sequential scan.
create index ads_video_asset_id_idx on public.ads (video_asset_id) where video_asset_id is not null;

-- Only the service role (Edge Functions) ever touches this table — no
-- client of any kind needs to read or write webhook bookkeeping.
alter table public.video_webhook_events enable row level security;
alter table public.video_webhook_events force row level security;
revoke all on public.video_webhook_events from authenticated, anon;

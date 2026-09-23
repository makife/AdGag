-- ============================================================================
-- 0015_analytics.sql
-- Phase H (Polish). Analytics foundation (CLAUDE.md section 26): a swipe
-- past a video is not a meaningful view on its own — distinct event types
-- let ranking/product analysis later ask more precise questions than "was
-- it shown."
-- ============================================================================

create type public.ad_event_type as enum (
  'impression',
  'play_started',
  'two_second_view',
  'completed',
  'rewatched',
  'shared',
  'sold',
  'ad_this'
);

create table public.ad_events (
  id bigint generated always as identity primary key,
  ad_id uuid not null references public.ads (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete set null,
  event_type public.ad_event_type not null,
  watch_ms integer,
  created_at timestamptz not null default now()
);

create index ad_events_ad_id_event_type_idx on public.ad_events (ad_id, event_type);

comment on table public.ad_events is
  'Write-only from the client (batched — see AdEventTracker in Flutter). No client select policy: this is raw event data for future ranking/analysis, not a user-facing feed.';

alter table public.ad_events enable row level security;
alter table public.ad_events force row level security;

-- A user may only ever record events as themselves. Plain RLS (not an
-- RPC) is enough here since there's no business-rule validation beyond
-- that — and the Supabase client's batch insert already sends N rows in
-- one request, which is the "batch, don't spam requests" section 26 asks
-- for.
create policy ad_events_insert_own
  on public.ad_events
  for insert
  with check (user_id = auth.uid());

-- No select/update/delete policy for authenticated/anon: this is
-- write-only from the client's perspective. Reading it back for ranking
-- inputs or a creator-facing stats view is future work.
revoke select, update, delete on public.ad_events from authenticated, anon;

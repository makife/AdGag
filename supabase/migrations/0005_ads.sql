-- ============================================================================
-- 0005_ads.sql
-- Phase B (Social Core) — "basic feed metadata". This migration defines the
-- full target shape of `ads` (CLAUDE.md section 25) so later phases only
-- add behavior, not columns. Video upload/processing (Phase C) and
-- engagement counters (Phase E) populate these columns via
-- SECURITY DEFINER functions / service-role Edge Functions — a client
-- never gets a general UPDATE on this table (see grants at the bottom).
-- ============================================================================

create type public.ad_status as enum (
  'draft',
  'uploading',
  'processing',
  'ready',
  'failed',
  'blocked',
  'deleted'
);

create type public.ad_visibility as enum (
  'public'
);

create table public.ads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  subject_id uuid not null references public.ad_subjects (id),

  caption text,
  constraint caption_length check (char_length(coalesce(caption, '')) <= 150),

  video_provider text,
  video_asset_id text,
  playback_id text,
  thumbnail_url text,

  -- Min ~2s / max 10s per CLAUDE.md section 4. Null while not yet processed.
  duration_ms integer,
  constraint duration_range check (duration_ms is null or duration_ms between 1500 and 10000),

  status public.ad_status not null default 'draft',
  visibility public.ad_visibility not null default 'public',

  -- AD THIS lineage (section 9). Self-referential; ON DELETE SET NULL so
  -- deleting an origin Ad doesn't cascade-delete everything inspired by it.
  inspired_by_ad_id uuid references public.ads (id) on delete set null,

  -- No FK yet: public.daily_challenges doesn't exist until its own
  -- migration (Phase F). Added there via
  -- `alter table ads add constraint ads_daily_challenge_id_fkey ...`.
  daily_challenge_id uuid,

  view_count bigint not null default 0,
  sold_count bigint not null default 0,
  comment_count bigint not null default 0,
  share_count bigint not null default 0,
  ad_this_count bigint not null default 0,
  constraint counters_non_negative check (
    view_count >= 0 and sold_count >= 0 and comment_count >= 0 and
    share_count >= 0 and ad_this_count >= 0
  ),

  created_at timestamptz not null default now(),
  published_at timestamptz,
  deleted_at timestamptz
);

-- Feed/query indexes (CLAUDE.md section 57).
create index ads_status_published_at_idx on public.ads (status, published_at desc);
create index ads_user_id_published_at_idx on public.ads (user_id, published_at desc);
create index ads_subject_id_published_at_idx on public.ads (subject_id, published_at desc);
create index ads_inspired_by_ad_id_idx on public.ads (inspired_by_ad_id) where inspired_by_ad_id is not null;

comment on table public.ads is
  'The content primitive (section 69): every short video is an Ad, always attached to exactly one AdSubject.';

-- ----------------------------------------------------------------------------
-- Keep ad_subjects.ads_count in sync without a COUNT(*) on every subject
-- page load (section 58). Counts a subject's Ads at the moment they first
-- become visible (ready) and reverses that when they stop being visible.
-- ----------------------------------------------------------------------------
create or replace function public.sync_ad_subject_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'ready' and old.status is distinct from 'ready' then
    update public.ad_subjects set ads_count = ads_count + 1 where id = new.subject_id;
  elsif old.status = 'ready' and new.status is distinct from 'ready' then
    update public.ad_subjects set ads_count = greatest(ads_count - 1, 0) where id = new.subject_id;
  end if;
  return new;
end;
$$;

create trigger ads_sync_subject_count
  after update of status on public.ads
  for each row
  execute function public.sync_ad_subject_count();

-- ----------------------------------------------------------------------------
-- Controlled write paths. There is deliberately no general INSERT/UPDATE
-- grant on this table for `authenticated` — every mutation is either a
-- narrowly-scoped RPC (below) or a future service-role Edge Function
-- (Phase C upload webhook, Phase E counters), never a raw client UPDATE of
-- status/counters/video_* columns (section 28/58/68).
-- ----------------------------------------------------------------------------
create or replace function public.create_draft_ad(p_subject_id uuid, p_caption text default null)
returns public.ads
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.ads;
begin
  insert into public.ads (user_id, subject_id, caption, status)
  values (auth.uid(), p_subject_id, p_caption, 'draft')
  returning * into result;
  return result;
end;
$$;

create or replace function public.update_draft_ad(p_ad_id uuid, p_subject_id uuid, p_caption text)
returns public.ads
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.ads;
begin
  update public.ads
  set subject_id = coalesce(p_subject_id, subject_id),
      caption = p_caption
  where id = p_ad_id and user_id = auth.uid() and status = 'draft'
  returning * into result;

  if not found then
    raise exception 'Ad not found, not a draft, or not owned by the current user';
  end if;
  return result;
end;
$$;

create or replace function public.delete_own_ad(p_ad_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.ads
  set status = 'deleted', deleted_at = now()
  where id = p_ad_id and user_id = auth.uid() and status <> 'deleted';

  if not found then
    raise exception 'Ad not found or not owned by the current user';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.ads enable row level security;
alter table public.ads force row level security;

-- Public feed visibility: only READY, non-deleted Ads are visible to
-- everyone (section 19: "Only READY Ads appear in normal feeds"). Owners
-- can also see their own Ads in every other state (drafts, processing,
-- failed) so the creation flow can show upload/processing status.
create policy ads_select_ready_or_own
  on public.ads
  for select
  using (status = 'ready' or auth.uid() = user_id);

-- No insert/update/delete policies: all writes go through the
-- SECURITY DEFINER functions above (which check auth.uid() = user_id
-- themselves) or a future service-role Edge Function.
revoke insert, update, delete on public.ads from authenticated, anon;

grant execute on function public.create_draft_ad(uuid, text) to authenticated;
grant execute on function public.update_draft_ad(uuid, uuid, text) to authenticated;
grant execute on function public.delete_own_ad(uuid) to authenticated;

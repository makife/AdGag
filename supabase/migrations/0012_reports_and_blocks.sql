-- ============================================================================
-- 0012_reports_and_blocks.sql
-- Phase G (Safety). CLAUDE.md section 30: "moderation is not optional."
-- Report flows for Ads/users/comments, a block graph, and block-aware
-- filtering applied to the two highest-traffic read paths (the main feed
-- and REVIEWS). See the note at the bottom about surfaces this does NOT
-- yet cover.
-- ============================================================================

create type public.report_target_type as enum ('ad', 'user', 'comment');

create type public.report_reason as enum (
  'nudity',
  'violence',
  'hate_harassment',
  'bullying',
  'dangerous_activity',
  'spam_scam',
  'copyright',
  'impersonation',
  'other'
);

create type public.report_status as enum ('pending', 'reviewed', 'actioned', 'dismissed');

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type public.report_target_type not null,
  target_id uuid not null,
  reason public.report_reason not null,
  details text,
  status public.report_status not null default 'pending',
  created_at timestamptz not null default now(),

  constraint details_length check (char_length(coalesce(details, '')) <= 500)
);

create index reports_status_created_at_idx on public.reports (status, created_at);
create index reports_target_idx on public.reports (target_type, target_id);

comment on table public.reports is
  'Report queue for Ads, users and comments. Reviewed by admin tooling outside this app (section 46) — never a Flutter admin UI.';

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (blocker_id, blocked_id),
  constraint blocks_no_self_block check (blocker_id <> blocked_id)
);

create index blocks_blocked_id_idx on public.blocks (blocked_id);

comment on table public.blocks is
  'One-directional block graph. Filtering treats a block as mutual (section 30: "disappear from each other''s experiences") even though only one side blocked.';

-- ----------------------------------------------------------------------------
-- Controlled write paths.
-- ----------------------------------------------------------------------------
create or replace function public.report_content(
  p_target_type public.report_target_type,
  p_target_id uuid,
  p_reason public.report_reason,
  p_details text default null
)
returns public.reports
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.reports;
begin
  insert into public.reports (reporter_id, target_type, target_id, reason, details)
  values (auth.uid(), p_target_type, p_target_id, p_reason, p_details)
  returning * into result;
  return result;
end;
$$;

create or replace function public.block_user(p_target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_target_user_id = auth.uid() then
    raise exception 'Cannot block yourself';
  end if;
  insert into public.blocks (blocker_id, blocked_id)
  values (auth.uid(), p_target_user_id)
  on conflict do nothing;

  -- Blocking implies unfollowing in both directions — staying mutually
  -- followed while blocked would contradict "disappear from each other's
  -- experiences" (section 30/31).
  delete from public.follows
  where (follower_id = auth.uid() and following_id = p_target_user_id)
     or (follower_id = p_target_user_id and following_id = auth.uid());
end;
$$;

create or replace function public.unblock_user(p_target_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_target_user_id;
$$;

-- Reusable predicate: true if either user has blocked the other. Used by
-- get_feed_page() and comments_select_visible below, and intended for
-- reuse anywhere else block-awareness is added later.
create or replace function public.is_blocked_either_way(p_user_a uuid, p_user_b uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = p_user_a and blocked_id = p_user_b)
       or (blocker_id = p_user_b and blocked_id = p_user_a)
  );
$$;

-- ----------------------------------------------------------------------------
-- Block-aware feed ranking. Restates get_feed_page() from 0010 with one
-- added filter — this is the "replace the function, not the client" seam
-- section 16/59 asks for.
-- ----------------------------------------------------------------------------
create or replace function public.get_feed_page(
  p_cursor_score double precision default null,
  p_cursor_id uuid default null,
  p_limit int default 10
)
returns table (
  id uuid, user_id uuid, subject_id uuid, caption text, playback_id text, thumbnail_url text,
  duration_ms integer, status public.ad_status, inspired_by_ad_id uuid, daily_challenge_id uuid,
  view_count bigint, sold_count bigint, comment_count bigint, share_count bigint, ad_this_count bigint,
  created_at timestamptz, published_at timestamptz,
  subject_display_name text, creator_username text, rank_score double precision
)
language sql
stable
as $$
  with scored as (
    select
      a.id, a.user_id, a.subject_id, a.caption, a.playback_id, a.thumbnail_url,
      a.duration_ms, a.status, a.inspired_by_ad_id, a.daily_challenge_id,
      a.view_count, a.sold_count, a.comment_count, a.share_count, a.ad_this_count,
      a.created_at, a.published_at,
      s.display_name as subject_display_name,
      p.username as creator_username,
      (
        (a.sold_count * 3 + a.ad_this_count * 5 + a.comment_count + 1)
        / power(greatest(extract(epoch from (now() - a.published_at)) / 3600.0, 0) + 2, 1.5)
      ) as rank_score
    from public.ads a
    join public.ad_subjects s on s.id = a.subject_id
    join public.profiles p on p.id = a.user_id
    where a.status = 'ready'
      and (auth.uid() is null or not public.is_blocked_either_way(auth.uid(), a.user_id))
  )
  select *
  from scored
  where
    p_cursor_score is null
    or rank_score < p_cursor_score
    or (rank_score = p_cursor_score and id < p_cursor_id)
  order by rank_score desc, id desc
  limit p_limit;
$$;

grant execute on function public.get_feed_page(double precision, uuid, int) to authenticated, anon;

-- ----------------------------------------------------------------------------
-- Block-aware REVIEWS visibility.
-- ----------------------------------------------------------------------------
drop policy comments_select_visible on public.comments;

create policy comments_select_visible
  on public.comments
  for select
  using (
    deleted_at is null
    and exists (
      select 1 from public.ads a
      where a.id = comments.ad_id
        and (a.status = 'ready' or a.user_id = auth.uid())
    )
    and (auth.uid() is null or not public.is_blocked_either_way(auth.uid(), comments.user_id))
  );

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.reports enable row level security;
alter table public.reports force row level security;
alter table public.blocks enable row level security;
alter table public.blocks force row level security;

-- Reports are not publicly readable at all — only the reporter's own
-- submissions (a small self-service "my reports" list), never other
-- users' reports or reports about oneself (would leak who reported you).
create policy reports_select_own
  on public.reports
  for select
  using (auth.uid() = reporter_id);

revoke insert, update, delete on public.reports from authenticated, anon;
grant execute on function public.report_content(public.report_target_type, uuid, public.report_reason, text) to authenticated;

-- A user may see their own block list (to manage it) but not who has
-- blocked them (section 31 — no tool for figuring out who blocked you).
create policy blocks_select_own
  on public.blocks
  for select
  using (auth.uid() = blocker_id);

revoke insert, update, delete on public.blocks from authenticated, anon;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- Known remaining gap (tracked here rather than silently assumed done):
-- block filtering is applied to the main feed and REVIEWS only. Subject
-- pages (fetchAdsForSubject), Market's Fresh Ads, profile Ads grids, and
-- search do NOT yet filter blocked users' content. Extend
-- is_blocked_either_way() into those queries when blocking sees real
-- usage — flagged explicitly rather than claimed as complete.
-- ----------------------------------------------------------------------------

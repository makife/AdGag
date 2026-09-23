-- ============================================================================
-- 0010_feed_ranking.sql
-- Phase F (Discovery). "MVP: Postgres-based candidate selection +
-- heuristic ranking" (CLAUDE.md section 59). Replaces the Phase B feed's
-- pure freshness ordering with a single, explicit, swappable scoring
-- function — not a recommendation engine (section 16: "Do NOT create a
-- machine-learning recommendation engine yet").
--
-- Score = engagement-weighted (SOLD counts 3x, AD THIS 5x — "AD THIS is a
-- particularly strong signal", section 16) divided by a smooth age decay,
-- the same shape as classic "hot" ranking formulas. AD THIS is weighted
-- highest because it is the strongest signal that an Ad caused more
-- content to be created — the core product loop (section 62).
--
-- Known MVP limitation: rank_score is computed from `now()` at query time,
-- not snapshotted, so an Ad's relative position can drift slightly between
-- page 1 and page 2 of the same scroll session if enough time passes
-- between requests. Acceptable at MVP scale; the fix (precomputed/cached
-- candidate pools) is explicitly Phase F->growth-stage work per section 59,
-- not something to build before it's needed.
-- ============================================================================

create or replace function public.get_feed_page(
  p_cursor_score double precision default null,
  p_cursor_id uuid default null,
  p_limit int default 10
)
returns table (
  id uuid,
  user_id uuid,
  subject_id uuid,
  caption text,
  playback_id text,
  thumbnail_url text,
  duration_ms integer,
  status public.ad_status,
  inspired_by_ad_id uuid,
  daily_challenge_id uuid,
  view_count bigint,
  sold_count bigint,
  comment_count bigint,
  share_count bigint,
  ad_this_count bigint,
  created_at timestamptz,
  published_at timestamptz,
  subject_display_name text,
  creator_username text,
  rank_score double precision
)
language sql
stable
-- Not SECURITY DEFINER: every row this reads (ready ads, active subjects,
-- non-deleted profiles) is already publicly selectable under the callers'
-- own RLS policies, so this runs with the caller's normal privileges
-- (least privilege — section 68).
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

comment on function public.get_feed_page(double precision, uuid, int) is
  'Ranked, keyset-paginated feed candidates. The one place feed ranking logic lives (section 16) — replace this function''s scoring, not the Flutter client, when ranking evolves.';

grant execute on function public.get_feed_page(double precision, uuid, int) to authenticated, anon;

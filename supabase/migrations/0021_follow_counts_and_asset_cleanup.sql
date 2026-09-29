-- ============================================================================
-- 0021_follow_counts_and_asset_cleanup.sql
--
-- 1. Maintained follower/following counters on profiles (CLAUDE.md section
--    58: counts shown on every profile must not need COUNT(*) per request).
--    Kept by a trigger on `follows`, so every path that adds/removes a follow
--    row — follow, unfollow, block (removes follows both ways), account
--    deletion (cascade) — keeps them right without extra code.
-- 2. `ads.video_asset_deleted_at`: set once the Mux asset of a deleted Ad
--    has actually been deleted at Mux (delete-ad / delete-account Edge
--    Functions, or Mux's own video.asset.deleted webhook). A deleted Ad with
--    this still null is a pending cleanup the Edge Functions retry.
-- ============================================================================

alter table public.profiles
  add column followers_count integer not null default 0,
  add column following_count integer not null default 0;

update public.profiles p
set followers_count = (select count(*) from public.follows f where f.following_id = p.id),
    following_count = (select count(*) from public.follows f where f.follower_id = p.id);

create or replace function public.maintain_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set followers_count = followers_count + 1 where id = new.following_id;
    update public.profiles set following_count = following_count + 1 where id = new.follower_id;
    return new;
  else
    -- greatest(): never negative, even if a row predates the backfill race.
    update public.profiles set followers_count = greatest(followers_count - 1, 0) where id = old.following_id;
    update public.profiles set following_count = greatest(following_count - 1, 0) where id = old.follower_id;
    return old;
  end if;
end;
$$;

-- Trigger-only function: nobody may call it directly (0017's lesson —
-- functions get EXECUTE for PUBLIC by default).
revoke all on function public.maintain_follow_counts() from public, anon, authenticated;

create trigger follows_maintain_counts
  after insert or delete on public.follows
  for each row
  execute function public.maintain_follow_counts();

-- Counters are server-maintained only. 0002 already limits authenticated
-- updates to display_name/avatar_url/bio, so these new columns are not
-- client-writable; stated here so a future grant change doesn't miss it.
revoke update (followers_count, following_count) on public.profiles from authenticated, anon;

alter table public.ads
  add column video_asset_deleted_at timestamptz;

-- Pending Mux cleanups: deleted Ads whose asset still exists at Mux.
create index ads_pending_asset_cleanup_idx
  on public.ads (user_id)
  where status = 'deleted' and video_asset_id is not null and video_asset_deleted_at is null;

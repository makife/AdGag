-- ============================================================================
-- 0023_counters_follow_row_deletes.sql
--
-- Device report: MARKET showed "Kumanda · 2 Ads" with only one Ad in it.
-- Cause: the maintained counters only reacted to STATUS updates / soft
-- deletes. Account deletion (0021's delete-account) removes rows outright —
-- the profile cascade deletes that user's Ads and reviews — and no counter
-- was told. Affected:
--   ad_subjects.ads_count              (their ready Ads deleted)
--   ads.ad_this_count                  (their AD THIS Ads deleted; also
--                                       never went down when such an Ad was
--                                       deleted or blocked normally)
--   daily_challenges.participant_count (same as ad_this_count)
--   ads.comment_count                  (their reviews on others' Ads deleted)
--   comments.reply_count               (their replies deleted)
-- Every counter now follows the Ad/review being visible, in both
-- directions, including hard deletes. All are recomputed at the end.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Ads: one function for all three Ad-driven counters, on UPDATE of status
-- and on DELETE. "Counted" = status 'ready'.
-- ---------------------------------------------------------------------------
create or replace function public.sync_ad_visibility_counters()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- NEW is null in a DELETE trigger, so each case reads only what exists.
  was_ready boolean := old.status = 'ready';
  is_ready boolean := false;
  delta int;
  row_subject uuid := old.subject_id;
  row_origin uuid := old.inspired_by_ad_id;
  row_challenge uuid := old.daily_challenge_id;
begin
  if tg_op = 'UPDATE' then
    is_ready := new.status = 'ready';
    row_subject := new.subject_id;
    row_origin := new.inspired_by_ad_id;
    row_challenge := new.daily_challenge_id;
  end if;
  if was_ready = is_ready then
    return null;
  end if;
  delta := case when is_ready then 1 else -1 end;

  update public.ad_subjects set ads_count = greatest(ads_count + delta, 0) where id = row_subject;
  if row_origin is not null then
    update public.ads set ad_this_count = greatest(ad_this_count + delta, 0) where id = row_origin;
  end if;
  if row_challenge is not null then
    update public.daily_challenges set participant_count = greatest(participant_count + delta, 0)
    where id = row_challenge;
  end if;
  return null;
end;
$$;

revoke all on function public.sync_ad_visibility_counters() from public, anon, authenticated;

drop trigger ads_sync_subject_count on public.ads;
drop trigger ads_sync_ad_this_count on public.ads;
drop trigger ads_sync_daily_challenge_participant_count on public.ads;
drop function public.sync_ad_subject_count();
drop function public.sync_ad_this_count();
drop function public.sync_daily_challenge_participant_count();

create trigger ads_sync_visibility_counters
  after update of status or delete on public.ads
  for each row
  execute function public.sync_ad_visibility_counters();

-- ---------------------------------------------------------------------------
-- Reviews: comment_count and reply_count also on hard DELETE of a review
-- that wasn't soft-deleted already.
-- ---------------------------------------------------------------------------
create or replace function public.sync_comment_counters_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.deleted_at is null then
    update public.ads set comment_count = greatest(comment_count - 1, 0) where id = old.ad_id;
    if old.parent_id is not null then
      update public.comments set reply_count = greatest(reply_count - 1, 0) where id = old.parent_id;
    end if;
  end if;
  return null;
end;
$$;

revoke all on function public.sync_comment_counters_on_delete() from public, anon, authenticated;

create trigger comments_sync_counters_on_delete
  after delete on public.comments
  for each row
  execute function public.sync_comment_counters_on_delete();

-- ---------------------------------------------------------------------------
-- Recompute everything from the rows as they are now.
-- ---------------------------------------------------------------------------
update public.ad_subjects s
set ads_count = (select count(*) from public.ads a where a.subject_id = s.id and a.status = 'ready');

update public.ads o
set ad_this_count = (select count(*) from public.ads a where a.inspired_by_ad_id = o.id and a.status = 'ready');

update public.daily_challenges d
set participant_count = (select count(*) from public.ads a where a.daily_challenge_id = d.id and a.status = 'ready');

update public.ads a
set comment_count = (select count(*) from public.comments c where c.ad_id = a.id and c.deleted_at is null);

update public.comments p
set reply_count = (select count(*) from public.comments c where c.parent_id = p.id and c.deleted_at is null);

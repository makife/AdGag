-- ============================================================================
-- 0017_fix_public_execute_grants.sql
-- Fixes a serious bug found by testing the live project directly: EVERY
-- function in this schema was callable by a completely anonymous caller.
--
-- Root cause: PostgreSQL grants EXECUTE on a newly created function to the
-- PUBLIC pseudo-role by default. Every prior migration's
-- `grant execute on function ... to authenticated` was additive on top of
-- that default — it never actually restricted anything, because `anon`
-- (and any other role) already had EXECUTE via PUBLIC regardless. This
-- was confirmed live: an anonymous request to create_draft_ad() reached
-- the function body and failed on an internal NOT NULL constraint instead
-- of being rejected for lacking a grant.
--
-- This migration:
--  1. Revokes EXECUTE FROM PUBLIC on every function in this schema that
--     should not be callable by anyone with the anon key.
--  2. Adds an explicit `if auth.uid() is null then raise exception`
--     guard at the top of every authenticated-required RPC, so a caller
--     that somehow still lacks a session gets one clear error message
--     instead of an internal implementation detail (e.g. a constraint
--     violation naming an internal table/column).
--  3. Converts the three RPCs that were `language sql` (mark_notification_
--     read, unblock_user, increment_share_count) to `language plpgsql`,
--     since a guard clause needs conditional logic SQL-language functions
--     can't express.
--  4. Adds rate limiting to increment_share_count, which every other
--     write-mutating RPC already had (section 29) but this one was
--     missed.
--
-- Trigger-only functions (handle_new_user, notify_*, sync_*,
-- set_updated_at, enforce_follow_rate_limit) and the enforce_rate_limit
-- helper are revoked from everyone — they're invoked by the trigger
-- mechanism or by other SECURITY DEFINER functions (which run as the
-- owner and need no grant), never directly by a client.
--
-- is_blocked_either_way() is DIFFERENT from the other helpers and is
-- deliberately NOT revoked from anon/authenticated: it's called from
-- get_feed_page() (SECURITY INVOKER, not DEFINER) and from the
-- comments_select_visible RLS policy, both of which execute as the
-- actual querying role, not as a privileged owner — revoking it would
-- silently break the feed and REVIEWS for every real user. (This does
-- mean it's technically callable as a standalone RPC too, which leaks
-- whether two arbitrary users have blocked each other — a real but minor
-- information disclosure; moving it to a schema PostgREST doesn't expose
-- would close that without affecting its two legitimate callers, and is
-- worth doing if this becomes a concern, but isn't done here.)
--
-- get_feed_page(), get_current_daily_challenge() and
-- canonicalize_subject_text() remain anon-callable — that's intentional,
-- matching the public-read RLS policies on the tables they read.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Trigger-only functions and internal helpers: no direct-call grant at
--    all, for anyone.
-- ----------------------------------------------------------------------------
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.notify_ad_this() from public, anon, authenticated;
revoke all on function public.notify_new_follower() from public, anon, authenticated;
revoke all on function public.notify_new_review() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.sync_ad_comment_count() from public, anon, authenticated;
revoke all on function public.sync_ad_sold_count() from public, anon, authenticated;
revoke all on function public.sync_ad_subject_count() from public, anon, authenticated;
revoke all on function public.sync_ad_this_count() from public, anon, authenticated;
revoke all on function public.sync_daily_challenge_participant_count() from public, anon, authenticated;
revoke all on function public.enforce_follow_rate_limit() from public, anon, authenticated;
revoke all on function public.enforce_rate_limit(text, int, interval) from public, anon, authenticated;

-- Revoke the PUBLIC default but restore anon+authenticated explicitly —
-- see the note above on why this one can't be locked down further.
revoke all on function public.is_blocked_either_way(uuid, uuid) from public;
grant execute on function public.is_blocked_either_way(uuid, uuid) to authenticated, anon;

-- ----------------------------------------------------------------------------
-- 2. Authenticated-required RPCs: restated with an explicit auth guard,
--    then PUBLIC/anon revoked and authenticated-only re-affirmed.
-- ----------------------------------------------------------------------------

create or replace function public.create_draft_ad(
  p_subject_id uuid,
  p_caption text default null,
  p_inspired_by_ad_id uuid default null,
  p_daily_challenge_id uuid default null
)
returns public.ads
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.ads;
  origin_is_ready boolean;
  challenge_is_current boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.enforce_rate_limit('create_draft_ad', 10, interval '1 hour');

  if p_inspired_by_ad_id is not null then
    select (status = 'ready') into origin_is_ready from public.ads where id = p_inspired_by_ad_id;
    if origin_is_ready is not true then
      raise exception 'Cannot AD THIS an ad that is not ready';
    end if;
  end if;

  if p_daily_challenge_id is not null then
    select (id is not null) into challenge_is_current
    from public.get_current_daily_challenge()
    where id = p_daily_challenge_id;
    if challenge_is_current is not true then
      raise exception 'That daily challenge is not currently active';
    end if;
  end if;

  insert into public.ads (user_id, subject_id, caption, status, inspired_by_ad_id, daily_challenge_id)
  values (auth.uid(), p_subject_id, p_caption, 'draft', p_inspired_by_ad_id, p_daily_challenge_id)
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.ads
  set status = 'deleted', deleted_at = now()
  where id = p_ad_id and user_id = auth.uid() and status <> 'deleted';

  if not found then
    raise exception 'Ad not found or not owned by the current user';
  end if;
end;
$$;

create or replace function public.toggle_sold_reaction(p_ad_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  already_sold boolean;
  ad_is_ready boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.enforce_rate_limit('toggle_sold_reaction', 100, interval '10 minutes');

  select exists(select 1 from public.sold_reactions where user_id = auth.uid() and ad_id = p_ad_id)
    into already_sold;

  if already_sold then
    delete from public.sold_reactions where user_id = auth.uid() and ad_id = p_ad_id;
    return false;
  end if;

  select (status = 'ready') into ad_is_ready from public.ads where id = p_ad_id;
  if ad_is_ready is not true then
    raise exception 'Ad is not available';
  end if;

  insert into public.sold_reactions (user_id, ad_id) values (auth.uid(), p_ad_id);
  return true;
end;
$$;

create or replace function public.create_comment(p_ad_id uuid, p_body text)
returns public.comments
language plpgsql
security definer
set search_path = public
as $$
declare
  ad_is_ready boolean;
  result public.comments;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.enforce_rate_limit('create_comment', 20, interval '10 minutes');

  select (status = 'ready') into ad_is_ready from public.ads where id = p_ad_id;
  if ad_is_ready is not true then
    raise exception 'Ad is not available';
  end if;

  insert into public.comments (ad_id, user_id, body)
  values (p_ad_id, auth.uid(), p_body)
  returning * into result;
  return result;
end;
$$;

create or replace function public.delete_own_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.comments
  set deleted_at = now()
  where id = p_comment_id and user_id = auth.uid() and deleted_at is null;

  if not found then
    raise exception 'Comment not found or not owned by the current user';
  end if;
end;
$$;

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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.enforce_rate_limit('report_content', 20, interval '1 hour');

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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_target_user_id = auth.uid() then
    raise exception 'Cannot block yourself';
  end if;
  insert into public.blocks (blocker_id, blocked_id)
  values (auth.uid(), p_target_user_id)
  on conflict do nothing;

  delete from public.follows
  where (follower_id = auth.uid() and following_id = p_target_user_id)
     or (follower_id = p_target_user_id and following_id = auth.uid());
end;
$$;

create or replace function public.unblock_user(p_target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_target_user_id;
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.notifications
  set read_at = now()
  where id = p_notification_id and recipient_id = auth.uid() and read_at is null;
end;
$$;

-- Rate limit added here (was missing — every other write RPC has one).
create or replace function public.increment_share_count(p_ad_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.enforce_rate_limit('increment_share_count', 60, interval '10 minutes');

  update public.ads set share_count = share_count + 1 where id = p_ad_id and status = 'ready';
end;
$$;

create or replace function public.get_or_create_ad_subject(input_text text, input_locale text default 'en')
returns public.ad_subjects
language plpgsql
security definer
set search_path = public
as $$
declare
  key text;
  existing_subject_id uuid;
  result public.ad_subjects;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  key := public.canonicalize_subject_text(input_text);

  if key = '' or char_length(input_text) > 60 then
    raise exception 'Invalid subject text';
  end if;

  select subject_id into existing_subject_id from public.ad_subject_aliases where alias_key = key;

  if existing_subject_id is not null then
    select * into result from public.ad_subjects where id = existing_subject_id;
    return result;
  end if;

  select * into result from public.ad_subjects where canonical_key = key;
  if found then
    return result;
  end if;

  insert into public.ad_subjects (canonical_key, display_name)
  values (key, trim(input_text))
  returning * into result;

  insert into public.ad_subject_aliases (alias_key, subject_id)
  values (key, result.id);

  if input_locale is not null and input_locale <> 'en' then
    insert into public.ad_subject_translations (subject_id, locale, display_name)
    values (result.id, input_locale, trim(input_text))
    on conflict do nothing;
  end if;

  return result;
end;
$$;

revoke all on function public.create_draft_ad(uuid, text, uuid, uuid) from public, anon;
revoke all on function public.update_draft_ad(uuid, uuid, text) from public, anon;
revoke all on function public.delete_own_ad(uuid) from public, anon;
revoke all on function public.toggle_sold_reaction(uuid) from public, anon;
revoke all on function public.create_comment(uuid, text) from public, anon;
revoke all on function public.delete_own_comment(uuid) from public, anon;
revoke all on function public.report_content(public.report_target_type, uuid, public.report_reason, text) from public, anon;
revoke all on function public.block_user(uuid) from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.increment_share_count(uuid) from public, anon;
revoke all on function public.get_or_create_ad_subject(text, text) from public, anon;

grant execute on function public.create_draft_ad(uuid, text, uuid, uuid) to authenticated;
grant execute on function public.update_draft_ad(uuid, uuid, text) to authenticated;
grant execute on function public.delete_own_ad(uuid) to authenticated;
grant execute on function public.toggle_sold_reaction(uuid) to authenticated;
grant execute on function public.create_comment(uuid, text) to authenticated;
grant execute on function public.delete_own_comment(uuid) to authenticated;
grant execute on function public.report_content(public.report_target_type, uuid, public.report_reason, text) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.increment_share_count(uuid) to authenticated;
grant execute on function public.get_or_create_ad_subject(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Intentionally public/anon-readable RPCs — revoke the (also-present)
--    PUBLIC grant and re-affirm explicitly via anon/authenticated instead,
--    so "this is meant to be public" is stated on purpose rather than
--    left as an unexamined default.
-- ----------------------------------------------------------------------------
revoke all on function public.get_feed_page(double precision, uuid, int) from public;
revoke all on function public.get_current_daily_challenge() from public;
revoke all on function public.canonicalize_subject_text(text) from public;

grant execute on function public.get_feed_page(double precision, uuid, int) to authenticated, anon;
grant execute on function public.get_current_daily_challenge() to authenticated, anon;
grant execute on function public.canonicalize_subject_text(text) to authenticated, anon;

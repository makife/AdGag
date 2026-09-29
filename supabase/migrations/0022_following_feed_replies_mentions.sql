-- ============================================================================
-- 0022_following_feed_replies_mentions.sql
--
-- Social features that feed the core loop instead of copying generic ones
-- (CLAUDE.md section 61):
--   1. FOLLOWING feed (section 15/16): Ads from people you follow, newest
--      first. Same row shape and keyset cursor as get_feed_page, so the
--      client's FeedRepository contract doesn't change — rank_score is
--      simply the publish time (epoch seconds) here.
--   2. REVIEW replies, one level deep (section 8: "Replies may be
--      implemented ... deep nested comment trees are not necessary").
--   3. @mentions in reviews → a notification for the mentioned user.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Following feed
-- ---------------------------------------------------------------------------
create or replace function public.get_following_feed_page(
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
      extract(epoch from a.published_at)::double precision as rank_score
    from public.follows f
    join public.ads a on a.user_id = f.following_id   -- ads(user_id, published_at) index
    join public.ad_subjects s on s.id = a.subject_id
    join public.profiles p on p.id = a.user_id
    where f.follower_id = auth.uid()
      and a.status = 'ready'
      and a.published_at is not null
      and not public.is_blocked_either_way(auth.uid(), a.user_id)
  )
  select *
  from scored
  where
    p_cursor_score is null
    or rank_score < p_cursor_score
    or (rank_score = p_cursor_score and id < p_cursor_id)
  order by rank_score desc, id desc
  limit least(greatest(p_limit, 1), 50);
$$;

comment on function public.get_following_feed_page(double precision, uuid, int) is
  'FOLLOWING feed: ready Ads by accounts the caller follows, newest first. Same shape/cursor as get_feed_page. Empty for anon.';

-- SECURITY INVOKER (RLS applies); only signed-in users have a following list.
revoke all on function public.get_following_feed_page(double precision, uuid, int) from public, anon;
grant execute on function public.get_following_feed_page(double precision, uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Replies (one level)
-- ---------------------------------------------------------------------------
alter table public.comments
  add column parent_id uuid references public.comments (id) on delete cascade,
  add column reply_count integer not null default 0;

create index comments_parent_id_created_at_idx on public.comments (parent_id, created_at)
  where parent_id is not null;

-- Top-level listing (the panel's main list) filters parent_id is null.
create index comments_ad_id_top_level_idx on public.comments (ad_id, created_at desc)
  where parent_id is null;

create or replace function public.sync_comment_reply_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.comments set reply_count = reply_count + 1 where id = new.parent_id;
  elsif tg_op = 'UPDATE' and new.parent_id is not null
        and old.deleted_at is null and new.deleted_at is not null then
    update public.comments set reply_count = greatest(reply_count - 1, 0) where id = new.parent_id;
  end if;
  return null;
end;
$$;

revoke all on function public.sync_comment_reply_count() from public, anon, authenticated;

create trigger comments_sync_reply_count
  after insert or update of deleted_at on public.comments
  for each row
  execute function public.sync_comment_reply_count();

-- create_comment gains p_parent_id. Adding a parameter creates a NEW
-- overload (the 0016 lesson), so the old signature is dropped explicitly.
drop function public.create_comment(uuid, text);

create function public.create_comment(p_ad_id uuid, p_body text, p_parent_id uuid default null)
returns public.comments
language plpgsql
security definer
set search_path = public
as $$
declare
  ad_is_ready boolean;
  parent public.comments;
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

  if p_parent_id is not null then
    select * into parent from public.comments where id = p_parent_id;
    if parent.id is null or parent.ad_id <> p_ad_id or parent.deleted_at is not null then
      raise exception 'Review not found';
    end if;
    if parent.parent_id is not null then
      raise exception 'Replies are one level deep';
    end if;
    if public.is_blocked_either_way(auth.uid(), parent.user_id) then
      raise exception 'Review not found';
    end if;
  end if;

  insert into public.comments (ad_id, user_id, body, parent_id)
  values (p_ad_id, auth.uid(), p_body, p_parent_id)
  returning * into result;
  return result;
end;
$$;

revoke all on function public.create_comment(uuid, text, uuid) from public, anon;
grant execute on function public.create_comment(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Notifications: replies and @mentions
-- ---------------------------------------------------------------------------
-- New enum values are only USED inside function bodies below, which are
-- not evaluated at creation time, so adding them in this same migration is
-- fine.
alter type public.notification_type add value if not exists 'review_reply';
alter type public.notification_type add value if not exists 'mention';

-- One trigger decides every notification a new review causes, so nobody is
-- notified twice for the same review (e.g. the Ad's creator who is also
-- @mentioned). Priority: reply > mention > new_review. Blocked pairs are
-- never notified.
create or replace function public.notify_new_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ad_owner_id uuid;
  parent_author_id uuid;
  notified uuid[] := array[new.user_id];  -- never notify the author
  mentioned record;
  payload jsonb := jsonb_build_object('ad_id', new.ad_id, 'comment_id', new.id);
begin
  if new.parent_id is not null then
    select user_id into parent_author_id from public.comments where id = new.parent_id;
    if parent_author_id is not null and not parent_author_id = any(notified)
       and not public.is_blocked_either_way(parent_author_id, new.user_id) then
      insert into public.notifications (recipient_id, actor_id, type, payload)
      values (parent_author_id, new.user_id, 'review_reply', payload || jsonb_build_object('parent_id', new.parent_id));
      notified := notified || parent_author_id;
    end if;
  end if;

  -- @username tokens (the username rule from 0002), at most 5 per review.
  for mentioned in
    select distinct p.id
    from (
      select lower(m[1]) as uname
      from regexp_matches(new.body, '@([A-Za-z][A-Za-z0-9_]{2,19})', 'g') as m
      limit 5
    ) t
    join public.profiles p on p.username = t.uname and p.account_status = 'active'
  loop
    if not mentioned.id = any(notified)
       and not public.is_blocked_either_way(mentioned.id, new.user_id) then
      insert into public.notifications (recipient_id, actor_id, type, payload)
      values (mentioned.id, new.user_id, 'mention', payload);
      notified := notified || mentioned.id;
    end if;
  end loop;

  select user_id into ad_owner_id from public.ads where id = new.ad_id;
  if ad_owner_id is not null and not ad_owner_id = any(notified)
     and not public.is_blocked_either_way(ad_owner_id, new.user_id) then
    insert into public.notifications (recipient_id, actor_id, type, payload)
    values (ad_owner_id, new.user_id, 'new_review', payload);
  end if;

  return new;
end;
$$;

revoke all on function public.notify_new_review() from public, anon, authenticated;

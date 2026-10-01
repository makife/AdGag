-- ============================================================================
-- 0025_review_likes_and_milestones.sql
--
--  1. Likes on REVIEWS (comments): comment_likes + comments.like_count
--     (trigger, insert AND delete — cascades from account/Ad deletion never
--     fire UPDATE triggers, see 0023) + toggle_comment_like RPC (rate
--     limited, refused across a block). No notification per like.
--  2. SOLD and GAG! (share) milestone notifications for the Ad's creator:
--     "Your Ad reached 100 SOLD". Each milestone fires once per Ad (an
--     un-SOLD/re-SOLD around a threshold doesn't repeat it), only for ready
--     Ads. Pushed like every other notification (0024); switchable via
--     notification_preferences.milestones.
--
-- NOTE: comment_likes has FKs to comments AND profiles, which makes a plain
-- `comments -> profiles(...)` PostgREST embed ambiguous (PGRST201, the
-- 0007/sold_reactions lesson). The app's comment queries name the FK
-- explicitly (profiles!comments_user_id_fkey) from this version on.
-- ============================================================================

-- ------------------------------------------------------------ review likes
create table public.comment_likes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  comment_id uuid not null references public.comments (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, comment_id)
);

create index comment_likes_comment_idx on public.comment_likes (comment_id);

alter table public.comments add column if not exists like_count integer not null default 0;

create or replace function public.sync_comment_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set like_count = like_count + 1 where id = new.comment_id;
    return new;
  end if;
  update public.comments set like_count = greatest(like_count - 1, 0) where id = old.comment_id;
  return old;
end;
$$;

revoke all on function public.sync_comment_like_count() from public, anon, authenticated;

create trigger comment_likes_sync_count
  after insert or delete on public.comment_likes
  for each row
  execute function public.sync_comment_like_count();

create or replace function public.toggle_comment_like(p_comment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  author uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  perform public.enforce_rate_limit('toggle_comment_like', 200, interval '10 minutes');

  if exists (select 1 from public.comment_likes where user_id = uid and comment_id = p_comment_id) then
    delete from public.comment_likes where user_id = uid and comment_id = p_comment_id;
    return false;
  end if;

  select user_id into author from public.comments where id = p_comment_id and deleted_at is null;
  if author is null then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  if public.is_blocked_either_way(author, uid) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;

  insert into public.comment_likes (user_id, comment_id) values (uid, p_comment_id);
  return true;
end;
$$;

revoke all on function public.toggle_comment_like(uuid) from public, anon;
grant execute on function public.toggle_comment_like(uuid) to authenticated;

alter table public.comment_likes enable row level security;
alter table public.comment_likes force row level security;

-- Each user sees only their OWN likes (the app embeds them to know which
-- reviews it has liked); counts come from comments.like_count.
create policy comment_likes_select_own
  on public.comment_likes for select using (auth.uid() = user_id);

revoke insert, update, delete on public.comment_likes from anon, authenticated;

-- -------------------------------------------------------------- milestones
alter type public.notification_type add value if not exists 'sold_milestone';
alter type public.notification_type add value if not exists 'gag_milestone';

alter table public.notification_preferences
  add column if not exists milestones boolean not null default true;

alter table public.ads
  add column if not exists sold_milestone_notified integer not null default 0,
  add column if not exists gag_milestone_notified integer not null default 0;

-- Highest milestone <= n (0 when below the first). n is bigint like the ads counters.
create or replace function public.milestone_at_or_below(n bigint, first_milestone integer)
returns integer
language sql
immutable
as $$
  select coalesce(max(m), 0)
  from unnest(array[1, 10, 50, 100, 500, 1000, 5000, 10000, 50000, 100000, 500000, 1000000]) as m
  where m >= first_milestone and m <= n;
$$;

-- Existing Ads: milestones already passed count as notified (no burst of
-- old milestones, no repeat when a count dips and comes back).
update public.ads
set sold_milestone_notified = public.milestone_at_or_below(sold_count, 1),
    gag_milestone_notified = public.milestone_at_or_below(share_count, 10);

create or replace function public.notify_ad_milestones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m integer;
begin
  if new.status <> 'ready' then
    return new;
  end if;

  m := public.milestone_at_or_below(new.sold_count, 1);
  if m > new.sold_milestone_notified then
    new.sold_milestone_notified := m;
    insert into public.notifications (recipient_id, actor_id, type, payload)
    values (new.user_id, null, 'sold_milestone', jsonb_build_object('ad_id', new.id, 'count', m));
  end if;

  m := public.milestone_at_or_below(new.share_count, 10);
  if m > new.gag_milestone_notified then
    new.gag_milestone_notified := m;
    insert into public.notifications (recipient_id, actor_id, type, payload)
    values (new.user_id, null, 'gag_milestone', jsonb_build_object('ad_id', new.id, 'count', m));
  end if;

  return new;
end;
$$;

revoke all on function public.notify_ad_milestones() from public, anon, authenticated;

create trigger ads_notify_milestones
  before update of sold_count, share_count on public.ads
  for each row
  execute function public.notify_ad_milestones();

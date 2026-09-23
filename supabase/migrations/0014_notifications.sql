-- ============================================================================
-- 0014_notifications.sql
-- Phase H (Polish). Notifications foundation (CLAUDE.md section 32):
-- new follower, REVIEWS, AD THIS attribution for now — Daily Ad
-- results/moderation notices are added when Phase F/G's admin tooling
-- actually produces those events. In-app (pull-based) list only; push
-- dispatch is a separate Edge Function documented in README.md, not
-- implemented here (needs FCM/APNs credentials this environment doesn't
-- have — section 67: don't block on a missing credential, but don't
-- fake the integration either).
-- ============================================================================

create type public.notification_type as enum ('new_follower', 'new_review', 'ad_this');

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  type public.notification_type not null,
  -- Small denormalized context (e.g. {"ad_id": "...", "comment_id": "..."})
  -- so the client can deep-link without a second fetch. Not a general
  -- event store — see ad_events below for that.
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc);

comment on table public.notifications is
  'In-app notification feed (ACTIVITY tab). Push delivery is a separate concern — see README.md > External Services.';

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  token text not null,
  created_at timestamptz not null default now(),

  unique (user_id, token)
);

comment on table public.device_tokens is
  'Registered for future push dispatch (section 32). Never read by the client itself — only written by it and read by a future push-sending Edge Function using the service role.';

-- ----------------------------------------------------------------------------
-- Notification-producing triggers. Each fires only on the specific
-- transition that should notify someone, not on every write, so
-- notifications aren't spammy (section 32: "Do not spam users").
-- ----------------------------------------------------------------------------
create or replace function public.notify_new_follower()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, payload)
  values (new.following_id, new.follower_id, 'new_follower', '{}'::jsonb);
  return new;
end;
$$;

create trigger follows_notify_new_follower
  after insert on public.follows
  for each row
  execute function public.notify_new_follower();

create or replace function public.notify_new_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ad_owner_id uuid;
begin
  select user_id into ad_owner_id from public.ads where id = new.ad_id;
  -- Don't notify creators about reviews on their own Ad from themselves.
  if ad_owner_id is not null and ad_owner_id <> new.user_id then
    insert into public.notifications (recipient_id, actor_id, type, payload)
    values (ad_owner_id, new.user_id, 'new_review', jsonb_build_object('ad_id', new.ad_id, 'comment_id', new.id));
  end if;
  return new;
end;
$$;

create trigger comments_notify_new_review
  after insert on public.comments
  for each row
  execute function public.notify_new_review();

create or replace function public.notify_ad_this()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  origin_owner_id uuid;
begin
  if new.status = 'ready' and old.status is distinct from 'ready' and new.inspired_by_ad_id is not null then
    select user_id into origin_owner_id from public.ads where id = new.inspired_by_ad_id;
    if origin_owner_id is not null and origin_owner_id <> new.user_id then
      insert into public.notifications (recipient_id, actor_id, type, payload)
      values (
        origin_owner_id, new.user_id, 'ad_this',
        jsonb_build_object('ad_id', new.id, 'origin_ad_id', new.inspired_by_ad_id)
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger ads_notify_ad_this
  after update of status on public.ads
  for each row
  execute function public.notify_ad_this();

-- ----------------------------------------------------------------------------
-- Controlled write path for marking read (the only client write this
-- table needs).
-- ----------------------------------------------------------------------------
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications
  set read_at = now()
  where id = p_notification_id and recipient_id = auth.uid() and read_at is null;
$$;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.notifications enable row level security;
alter table public.notifications force row level security;

create policy notifications_select_own
  on public.notifications
  for select
  using (auth.uid() = recipient_id);

revoke insert, update, delete on public.notifications from authenticated, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;

alter table public.device_tokens enable row level security;
alter table public.device_tokens force row level security;

create policy device_tokens_select_own
  on public.device_tokens
  for select
  using (auth.uid() = user_id);

create policy device_tokens_insert_own
  on public.device_tokens
  for insert
  with check (auth.uid() = user_id);

create policy device_tokens_delete_own
  on public.device_tokens
  for delete
  using (auth.uid() = user_id);

revoke update on public.device_tokens from authenticated, anon;

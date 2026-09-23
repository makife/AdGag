-- ============================================================================
-- 0011_daily_challenges.sql
-- Phase F (Discovery). TODAY'S AD (CLAUDE.md section 11). Time boundaries
-- are server-controlled: the client only ever displays what
-- get_current_daily_challenge() says is active, never computes "is today's
-- challenge live" from the device clock.
-- ============================================================================

create type public.daily_challenge_status as enum ('scheduled', 'active', 'ended', 'cancelled');

create table public.daily_challenges (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.ad_subjects (id),
  title text not null,
  prompt text not null,
  icon_url text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- Administrative override (e.g. `cancelled`); day-to-day active/ended
  -- state is derived from starts_at/ends_at at read time, not trusted from
  -- this column alone — see get_current_daily_challenge() below.
  status public.daily_challenge_status not null default 'scheduled',
  participant_count bigint not null default 0,
  created_at timestamptz not null default now(),

  constraint valid_challenge_window check (ends_at > starts_at)
);

create index daily_challenges_window_idx on public.daily_challenges (starts_at, ends_at);

comment on table public.daily_challenges is
  'TODAY''S AD. For MVP a single UTC-based global challenge day (section 11) — one row is expected to be "current" at a time, not enforced by a constraint since a brief overlap during manual scheduling is harmless.';

-- Now that daily_challenges exists, wire up the FK that
-- 0005_ads.sql deliberately left off.
alter table public.ads
  add constraint ads_daily_challenge_id_fkey
  foreign key (daily_challenge_id) references public.daily_challenges (id);

-- ----------------------------------------------------------------------------
-- The one server-controlled source of truth for "what's today's challenge
-- right now" — never derived client-side from device time (section 11).
-- ----------------------------------------------------------------------------
create or replace function public.get_current_daily_challenge()
returns public.daily_challenges
language sql
stable
as $$
  select *
  from public.daily_challenges
  where status <> 'cancelled'
    and now() between starts_at and ends_at
  order by starts_at desc
  limit 1;
$$;

grant execute on function public.get_current_daily_challenge() to authenticated, anon;

-- ----------------------------------------------------------------------------
-- create_draft_ad gains an optional daily_challenge_id, validated against
-- the currently-active challenge server-side (never trust a client-sent
-- "this ad belongs to today's challenge" without checking the window).
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

grant execute on function public.create_draft_ad(uuid, text, uuid, uuid) to authenticated;

-- Counts a participant only once their Ad is actually published, same
-- reasoning as ad_this_count (section 16: finished content, not drafts).
create or replace function public.sync_daily_challenge_participant_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'ready' and old.status is distinct from 'ready' and new.daily_challenge_id is not null then
    update public.daily_challenges
    set participant_count = participant_count + 1
    where id = new.daily_challenge_id;
  end if;
  return new;
end;
$$;

create trigger ads_sync_daily_challenge_participant_count
  after update of status on public.ads
  for each row
  execute function public.sync_daily_challenge_participant_count();

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.daily_challenges enable row level security;
alter table public.daily_challenges force row level security;

create policy daily_challenges_select_public
  on public.daily_challenges
  for select
  using (true);

-- No insert/update/delete policies: challenge scheduling is an admin
-- operation (Phase G/H tooling), never a client write (section 46).
revoke insert, update, delete on public.daily_challenges from authenticated, anon;

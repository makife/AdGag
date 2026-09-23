-- ============================================================================
-- 0013_rate_limiting.sql
-- Phase G (Safety). CLAUDE.md section 29: "Do not assume RLS alone solves
-- abuse." Adds a generic per-user/per-action rate limit and wires it into
-- the abuse vectors section 29 names explicitly: comment spam, follow
-- spam, SOLD spam, upload spam, report abuse.
-- ============================================================================

create table public.rate_limit_events (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  action text not null,
  created_at timestamptz not null default now()
);

-- Supports "count this user's events for this action in the last N
-- minutes" — the only query pattern enforce_rate_limit() runs.
create index rate_limit_events_lookup_idx on public.rate_limit_events (user_id, action, created_at desc);

comment on table public.rate_limit_events is
  'Sliding-window rate limit log. Not user-facing data — no RLS select policy is needed since only enforce_rate_limit() (SECURITY DEFINER) ever reads it.';

create or replace function public.enforce_rate_limit(p_action text, p_max_count int, p_window interval)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count int;
begin
  select count(*) into recent_count
  from public.rate_limit_events
  where user_id = auth.uid()
    and action = p_action
    and created_at > now() - p_window;

  if recent_count >= p_max_count then
    raise exception 'You''re doing that too much right now. Try again in a bit.';
  end if;

  insert into public.rate_limit_events (user_id, action) values (auth.uid(), p_action);
end;
$$;

alter table public.rate_limit_events enable row level security;
alter table public.rate_limit_events force row level security;
revoke all on public.rate_limit_events from authenticated, anon;

-- ----------------------------------------------------------------------------
-- Wire the limit into each abuse vector section 29 names. Each function is
-- restated in full (CREATE OR REPLACE, per the additive-migration pattern
-- used throughout) with one added `perform enforce_rate_limit(...)` line.
-- ----------------------------------------------------------------------------

-- Comment spam: 20 REVIEWS per 10 minutes.
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

-- SOLD spam: 100 toggles per 10 minutes (generous — rapid double-taps are
-- normal UI use, not abuse; this stops scripted mass-reacting).
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

-- Upload spam: 10 new drafts per hour.
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

-- Report abuse: 20 reports per hour (prevents mass-reporting a target to
-- harass them via repeated review flags, section 29/31).
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
  perform public.enforce_rate_limit('report_content', 20, interval '1 hour');

  insert into public.reports (reporter_id, target_type, target_id, reason, details)
  values (auth.uid(), p_target_type, p_target_id, p_reason, p_details)
  returning * into result;
  return result;
end;
$$;

-- Follow spam: 30 new follows per 10 minutes. Unlike the RPCs above,
-- `follows` is written via direct RLS-governed INSERT (Phase B), so this
-- is enforced with a trigger instead of an RPC body.
create or replace function public.enforce_follow_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enforce_rate_limit('follow', 30, interval '10 minutes');
  return new;
end;
$$;

create trigger follows_rate_limit
  before insert on public.follows
  for each row
  execute function public.enforce_follow_rate_limit();

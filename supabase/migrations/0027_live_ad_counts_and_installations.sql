-- ============================================================================
-- 0027_live_ad_counts_and_installations.sql
--
--  1. Live counters. When an Ad's SOLD / REVIEWS / GAG! / AD THIS counts
--     change, the database broadcasts JUST those numbers on the public
--     Realtime topic "ad-counts:<ad id>" (event "counts"). The app listens
--     only for the Ad on screen, so a review or SOLD from someone else shows
--     up at once. Broadcast (realtime.send), not postgres_changes on `ads`:
--     that would ship the whole row (incl. internal fields such as the video
--     asset id) to every listener. Never blocks the write that caused it.
--
--  2. Device installations. register_device_token gains an installation id
--     (a random id the app keeps per install): registering replaces any
--     other token this installation registered before (token refresh,
--     language change, account switch), so one phone no longer piles up
--     tokens and gets the same push several times. The 3-argument version
--     stays for builds before 0.1.17 (no default arguments on either, so
--     PostgREST picks by the named arguments without ambiguity — see 0016).
-- ============================================================================

-- ------------------------------------------------------------ live counts
create or replace function public.broadcast_ad_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.sold_count is distinct from old.sold_count
     or new.comment_count is distinct from old.comment_count
     or new.share_count is distinct from old.share_count
     or new.ad_this_count is distinct from old.ad_this_count then
    perform realtime.send(
      jsonb_build_object(
        'ad_id', new.id,
        'sold', new.sold_count,
        'comments', new.comment_count,
        'shares', new.share_count,
        'ad_this', new.ad_this_count
      ),
      'counts',
      'ad-counts:' || new.id::text,
      false
    );
  end if;
  return null;
exception when others then
  raise warning 'broadcast_ad_counts failed: %', sqlerrm;
  return null;
end;
$$;

revoke all on function public.broadcast_ad_counts() from public, anon, authenticated;

create trigger ads_broadcast_counts
  after update of sold_count, comment_count, share_count, ad_this_count on public.ads
  for each row
  execute function public.broadcast_ad_counts();

-- ---------------------------------------------------------- installations
alter table public.device_tokens add column if not exists installation_id text;

create index if not exists device_tokens_installation_idx on public.device_tokens (installation_id);

create or replace function public.register_device_token(
  p_token text,
  p_platform text,
  p_locale text,
  p_installation_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_platform not in ('ios', 'android') or length(coalesce(p_token, '')) not between 10 and 4096
     or length(coalesce(p_installation_id, '')) not between 8 and 64 then
    raise exception 'Invalid device token' using errcode = '22023';
  end if;
  -- This installation's earlier tokens (any account) and this token under
  -- any other account: the phone now has exactly one row.
  delete from public.device_tokens
  where (installation_id = p_installation_id and token <> p_token)
     or (token = p_token and user_id <> uid);
  insert into public.device_tokens (user_id, platform, token, locale, installation_id)
  values (uid, p_platform, p_token, left(coalesce(nullif(p_locale, ''), 'en'), 8), p_installation_id)
  on conflict (user_id, token) do update
    set platform = excluded.platform,
        locale = excluded.locale,
        installation_id = excluded.installation_id,
        updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text, text, text) from public, anon;
grant execute on function public.register_device_token(text, text, text, text) to authenticated;

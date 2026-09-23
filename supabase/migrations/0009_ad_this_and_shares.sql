-- ============================================================================
-- 0009_ad_this_and_shares.sql
-- Phase E (Engagement). AD THIS (CLAUDE.md section 9 — "one of the
-- defining mechanics") and external share tracking (section 33).
-- ============================================================================

-- create_draft_ad gains an optional inspired_by_ad_id. CREATE OR REPLACE
-- can add a new trailing parameter with a default and still replace the
-- original 0005_ads.sql function (Postgres allows this specific case);
-- restated in full since migrations are additive scripts, not diffs.
create or replace function public.create_draft_ad(
  p_subject_id uuid,
  p_caption text default null,
  p_inspired_by_ad_id uuid default null
)
returns public.ads
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.ads;
  origin_is_ready boolean;
begin
  if p_inspired_by_ad_id is not null then
    select (status = 'ready') into origin_is_ready from public.ads where id = p_inspired_by_ad_id;
    if origin_is_ready is not true then
      raise exception 'Cannot AD THIS an ad that is not ready';
    end if;
  end if;

  insert into public.ads (user_id, subject_id, caption, status, inspired_by_ad_id)
  values (auth.uid(), p_subject_id, p_caption, 'draft', p_inspired_by_ad_id)
  returning * into result;
  return result;
end;
$$;

-- Counts a lineage edge only once the inspired Ad is actually published,
-- not merely drafted — "a video that causes other people to create
-- content is valuable" (section 16) means finished content, not
-- abandoned drafts.
create or replace function public.sync_ad_this_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'ready' and old.status is distinct from 'ready' and new.inspired_by_ad_id is not null then
    update public.ads set ad_this_count = ad_this_count + 1 where id = new.inspired_by_ad_id;
  end if;
  return new;
end;
$$;

create trigger ads_sync_ad_this_count
  after update of status on public.ads
  for each row
  execute function public.sync_ad_this_count();

-- ----------------------------------------------------------------------------
-- Share count. A native share-sheet invocation is a UX signal, not a
-- security-relevant one — but it still goes through a controlled RPC
-- (never a direct column grant) so it stays a single, rate-limitable
-- choke point rather than an open counter (section 28/29/58).
-- ----------------------------------------------------------------------------
create or replace function public.increment_share_count(p_ad_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ads set share_count = share_count + 1 where id = p_ad_id and status = 'ready';
$$;

grant execute on function public.create_draft_ad(uuid, text, uuid) to authenticated;
grant execute on function public.increment_share_count(uuid) to authenticated;

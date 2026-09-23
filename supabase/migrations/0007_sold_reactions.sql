-- ============================================================================
-- 0007_sold_reactions.sql
-- Phase E (Engagement). SOLD is the primary positive reaction (CLAUDE.md
-- section 7/69) — functionally a like, but the mechanic is "press again to
-- remove", enforced here as a single atomic toggle RPC rather than trusting
-- the client to insert-then-delete correctly itself.
-- ============================================================================

create table public.sold_reactions (
  user_id uuid not null references public.profiles (id) on delete cascade,
  ad_id uuid not null references public.ads (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (user_id, ad_id)
);

create index sold_reactions_ad_id_idx on public.sold_reactions (ad_id);

comment on table public.sold_reactions is
  '"This ad sold me." One row per (user, ad) — the primary key is the section 28 uniqueness guarantee, not application logic.';

-- ----------------------------------------------------------------------------
-- Keeps ads.sold_count in sync without COUNT(*) per feed render (section
-- 58), the same pattern as ad_subjects.ads_count in 0005_ads.sql.
-- ----------------------------------------------------------------------------
create or replace function public.sync_ad_sold_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.ads set sold_count = sold_count + 1 where id = new.ad_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.ads set sold_count = greatest(sold_count - 1, 0) where id = old.ad_id;
    return old;
  end if;
  return null;
end;
$$;

create trigger sold_reactions_sync_count
  after insert or delete on public.sold_reactions
  for each row
  execute function public.sync_ad_sold_count();

-- ----------------------------------------------------------------------------
-- Single controlled write path. A toggle RPC (rather than separate
-- insert/delete RLS policies) means "can only SOLD a READY ad" is checked
-- in exactly one place, and two rapid taps can't race into an inconsistent
-- client-vs-server state.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.sold_reactions enable row level security;
alter table public.sold_reactions force row level security;

-- Public select: the feed needs "did I SOLD this" for the current user
-- (filtered client-side to `user_id = auth.uid()`), and reaction rows
-- carry nothing sensitive.
create policy sold_reactions_select_public
  on public.sold_reactions
  for select
  using (true);

-- No insert/update/delete policies: everything goes through
-- toggle_sold_reaction() (SECURITY DEFINER), which is where "only on a
-- READY ad" and "one per user" are actually enforced.
revoke insert, update, delete on public.sold_reactions from authenticated, anon;

grant execute on function public.toggle_sold_reaction(uuid) to authenticated;

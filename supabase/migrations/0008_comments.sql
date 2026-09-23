-- ============================================================================
-- 0008_comments.sql
-- Phase E (Engagement). REVIEWS in the product's language, `comments` in
-- the schema (CLAUDE.md section 8: "Backend entity can remain comments").
-- Create/delete-own/pagination now; report integration is Phase G once
-- the `reports` table exists.
-- ============================================================================

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.ads (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint comment_body_length check (char_length(body) between 1 and 500)
);

-- Cursor pagination support (section 8/57): comments for one Ad, newest
-- (or oldest, for a chronological reading order) first.
create index comments_ad_id_created_at_idx on public.comments (ad_id, created_at desc);

comment on table public.comments is
  'REVIEWS in product language. Soft-deleted via deleted_at so comment_count and any reply threading (future) stay consistent.';

create or replace function public.sync_ad_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.ads set comment_count = comment_count + 1 where id = new.ad_id;
    return new;
  elsif tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null then
    update public.ads set comment_count = greatest(comment_count - 1, 0) where id = new.ad_id;
    return new;
  end if;
  return null;
end;
$$;

create trigger comments_sync_count
  after insert or update of deleted_at on public.comments
  for each row
  execute function public.sync_ad_comment_count();

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
  update public.comments
  set deleted_at = now()
  where id = p_comment_id and user_id = auth.uid() and deleted_at is null;

  if not found then
    raise exception 'Comment not found or not owned by the current user';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.comments enable row level security;
alter table public.comments force row level security;

-- Mirrors the ads_select_ready_or_own visibility rule (0005_ads.sql) so
-- comments never leak on an Ad the viewer couldn't otherwise see.
create policy comments_select_visible
  on public.comments
  for select
  using (
    deleted_at is null
    and exists (
      select 1 from public.ads a
      where a.id = comments.ad_id
        and (a.status = 'ready' or a.user_id = auth.uid())
    )
  );

-- No insert/update/delete policies: writes go through create_comment() /
-- delete_own_comment() (SECURITY DEFINER), which is where "ad must be
-- ready" and "delete only your own" are actually enforced.
revoke insert, update, delete on public.comments from authenticated, anon;

grant execute on function public.create_comment(uuid, text) to authenticated;
grant execute on function public.delete_own_comment(uuid) to authenticated;

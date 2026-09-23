-- ============================================================================
-- 0003_follows.sql
-- Phase B (Social Core). Follow graph. CLAUDE.md section 15.
-- ============================================================================

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);

-- Primary key already gives us the (follower_id, following_id) uniqueness
-- CLAUDE.md section 28 requires; this index supports the reverse lookup
-- ("who follows me" / follower counts) which the PK's leading column can't.
create index follows_following_id_idx on public.follows (following_id);
create index follows_follower_id_idx on public.follows (follower_id);

alter table public.follows enable row level security;
alter table public.follows force row level security;

-- The follow graph itself is public (follower/following counts, "follows
-- you" badges), same as most social apps.
create policy follows_select_public
  on public.follows
  for select
  using (true);

-- A user may only ever create a follow row *as themselves* — the client
-- cannot forge follower_id for another user (section 28).
create policy follows_insert_own
  on public.follows
  for insert
  with check (auth.uid() = follower_id);

-- Unfollow = delete your own follow row.
create policy follows_delete_own
  on public.follows
  for delete
  using (auth.uid() = follower_id);

-- No update policy: a follow relationship is created/destroyed, never
-- edited in place.
revoke update on public.follows from authenticated, anon;

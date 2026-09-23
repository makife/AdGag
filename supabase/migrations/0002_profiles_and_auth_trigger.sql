-- ============================================================================
-- 0002_profiles_and_auth_trigger.sql
-- Phase A (Foundation) / pulled in early from Phase B because auth is not
-- meaningfully testable without a profile row. Phase B's migration extends
-- this table with social-graph-facing counters once follows/ads exist.
-- ============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  display_name text,
  avatar_url text,
  bio text,
  account_status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Mirrors core/utils/username_validator.dart. The client normalizes for
  -- UX; this CHECK is the actual enforcement point (CLAUDE.md section 24:
  -- "Do not trust client-side validation alone").
  constraint username_format check (username ~ '^[a-z][a-z0-9_]{2,19}$'),
  constraint bio_length check (char_length(coalesce(bio, '')) <= 300)
);

create unique index profiles_username_key on public.profiles (username);

comment on table public.profiles is
  'Public-facing user profile. Email/auth identity stays in auth.users and is never exposed here (section 45).';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Auto-provision a profile row whenever a new auth identity is created, so
-- the client never inserts its own profile (which would let it forge `id`
-- or bypass the username uniqueness/format rules). Runs as SECURITY DEFINER
-- specifically to bypass RLS for this one controlled insert path.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate_username text;
  final_username text;
  attempt int := 0;
begin
  candidate_username := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));

  if candidate_username !~ '^[a-z][a-z0-9_]{2,19}$' then
    -- No valid username supplied (e.g. OAuth sign-in with no metadata yet) —
    -- derive a safe placeholder the user can change later once profile
    -- editing ships, instead of failing the whole sign-up transaction.
    candidate_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 12);
  end if;

  final_username := candidate_username;

  loop
    begin
      insert into public.profiles (id, username, display_name)
      values (new.id, final_username, candidate_username);
      exit;
    exception when unique_violation then
      attempt := attempt + 1;
      exit when attempt > 5; -- give up rather than loop forever; surfaces as a clear error
      -- Truncate before appending the retry suffix so the result can never
      -- exceed the 20-char username_format CHECK regardless of how long
      -- candidate_username was (otherwise a max-length collision would
      -- raise check_violation here, which this handler doesn't catch).
      final_username := left(candidate_username, 14) || '_' || floor(random() * 10000)::int;
    end;
  end loop;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- Row Level Security (CLAUDE.md section 28 — mandatory).
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

-- Profiles are public read (usernames/avatars are inherently public in a
-- social app), but soft-deleted accounts are hidden from normal reads.
create policy profiles_select_public
  on public.profiles
  for select
  using (account_status <> 'deleted');

-- No insert policy: rows are created exclusively by handle_new_user()
-- (SECURITY DEFINER), so authenticated/anon get zero insert grants below.
-- No delete policy either — account deletion is a moderated workflow
-- (section 44/46), not a direct row delete.

create policy profiles_update_own
  on public.profiles
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Column-level privileges (defense in depth beyond row-level policies):
-- a user may edit their own display fields, but never their own
-- account_status, username, or id — even though the row-level policy above
-- would otherwise permit updating the row.
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_url, bio) on public.profiles to authenticated;

revoke insert, delete on public.profiles from authenticated, anon;

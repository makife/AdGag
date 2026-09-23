-- ============================================================================
-- 0004_ad_subjects.sql
-- Phase B (Social Core). AdSubject as a first-class entity, with a
-- normalization/alias strategy so "Sock", "SOCK", "socks" converge while
-- deliberately distinct custom subjects like "MY HUSBAND'S SOCKS" do not
-- (CLAUDE.md section 10).
-- ============================================================================

create table public.ad_subjects (
  id uuid primary key default gen_random_uuid(),

  -- The normalized dedupe key: lowercased, trimmed, internal whitespace
  -- collapsed to single spaces. This is deliberately *light-touch*
  -- normalization (no stemming/pluralization) so we don't over-merge
  -- creative subjects the product wants to keep distinct — see
  -- canonicalize_subject_text() below.
  canonical_key text not null unique,

  -- Display name as first entered (creator's language). Per-locale
  -- overrides live in ad_subject_translations; this is the fallback.
  display_name text not null,

  ads_count bigint not null default 0,
  status public.moderation_status not null default 'active',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint display_name_length check (char_length(display_name) between 1 and 60)
);

create index ad_subjects_status_ads_count_idx
  on public.ad_subjects (status, ads_count desc);

create trigger ad_subjects_set_updated_at
  before update on public.ad_subjects
  for each row
  execute function public.set_updated_at();

comment on table public.ad_subjects is
  'First-class subject entity (e.g. SOCK, MONDAY). Not a hashtag — every Ad belongs to exactly one subject (section 3).';

-- ----------------------------------------------------------------------------
-- Aliases: alternate spellings/plurals that resolve to the same subject,
-- e.g. "socks" -> SOCK. Distinct from ad_subjects.canonical_key so a
-- subject can accumulate aliases over time without renaming itself.
-- ----------------------------------------------------------------------------
create table public.ad_subject_aliases (
  alias_key text primary key,
  subject_id uuid not null references public.ad_subjects (id) on delete cascade
);

create index ad_subject_aliases_subject_id_idx on public.ad_subject_aliases (subject_id);

-- ----------------------------------------------------------------------------
-- Per-locale display names (section 34). Optional — falls back to
-- ad_subjects.display_name when no translation exists for a locale. This is
-- intentionally a flat key-value table, not a general translation
-- ontology, per "do not overbuild."
-- ----------------------------------------------------------------------------
create table public.ad_subject_translations (
  subject_id uuid not null references public.ad_subjects (id) on delete cascade,
  locale text not null,
  display_name text not null,

  primary key (subject_id, locale),
  constraint translation_display_name_length check (char_length(display_name) between 1 and 60)
);

-- ----------------------------------------------------------------------------
-- Normalization function. Deliberately conservative: lowercase + trim +
-- collapse whitespace only. No stemming/singularization — CLAUDE.md is
-- explicit that "MY HUSBAND'S SOCKS" must NOT collapse into "SOCK".
-- Alias-based merging (SOCK/socks) is opt-in, curated data in
-- ad_subject_aliases, not automatic linguistic inference.
-- ----------------------------------------------------------------------------
create or replace function public.canonicalize_subject_text(input text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(coalesce(input, '')), '\s+', ' ', 'g'));
$$;

-- ----------------------------------------------------------------------------
-- Single controlled write path for subject creation/lookup. Runs as
-- SECURITY DEFINER so normal users get INSERT on neither ad_subjects nor
-- ad_subject_aliases directly (see grants below) — every subject a client
-- can select or create for an Ad goes through here, keeping canonicalization
-- logic in one place instead of duplicated client-side.
-- ----------------------------------------------------------------------------
create or replace function public.get_or_create_ad_subject(input_text text, input_locale text default 'en')
returns public.ad_subjects
language plpgsql
security definer
set search_path = public
as $$
declare
  key text;
  existing_subject_id uuid;
  result public.ad_subjects;
begin
  key := public.canonicalize_subject_text(input_text);

  if key = '' or char_length(input_text) > 60 then
    raise exception 'Invalid subject text';
  end if;

  select subject_id into existing_subject_id from public.ad_subject_aliases where alias_key = key;

  if existing_subject_id is not null then
    select * into result from public.ad_subjects where id = existing_subject_id;
    return result;
  end if;

  select * into result from public.ad_subjects where canonical_key = key;
  if found then
    return result;
  end if;

  insert into public.ad_subjects (canonical_key, display_name)
  values (key, trim(input_text))
  returning * into result;

  insert into public.ad_subject_aliases (alias_key, subject_id)
  values (key, result.id);

  if input_locale is not null and input_locale <> 'en' then
    insert into public.ad_subject_translations (subject_id, locale, display_name)
    values (result.id, input_locale, trim(input_text))
    on conflict do nothing;
  end if;

  return result;
end;
$$;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.ad_subjects enable row level security;
alter table public.ad_subjects force row level security;
alter table public.ad_subject_aliases enable row level security;
alter table public.ad_subject_aliases force row level security;
alter table public.ad_subject_translations enable row level security;
alter table public.ad_subject_translations force row level security;

create policy ad_subjects_select_public
  on public.ad_subjects
  for select
  using (status = 'active');

create policy ad_subject_aliases_select_public
  on public.ad_subject_aliases
  for select
  using (true);

create policy ad_subject_translations_select_public
  on public.ad_subject_translations
  for select
  using (true);

-- No insert/update/delete policies on any of the three tables: all writes
-- go through get_or_create_ad_subject() (SECURITY DEFINER) or future
-- moderation tooling. ads_count is maintained by a trigger added in
-- 0005_ads.sql, never by the client directly (section 28/58).
revoke insert, update, delete on public.ad_subjects from authenticated, anon;
revoke insert, update, delete on public.ad_subject_aliases from authenticated, anon;
revoke insert, update, delete on public.ad_subject_translations from authenticated, anon;

grant execute on function public.get_or_create_ad_subject(text, text) to authenticated;

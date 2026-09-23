-- ============================================================================
-- 0001_extensions_and_common.sql
-- Phase A (Foundation). Extensions and small reusable helpers that every
-- later migration depends on. Nothing app-specific lives here.
-- ============================================================================

-- gen_random_uuid() for UUID primary keys (CLAUDE.md section 23).
create extension if not exists pgcrypto;

-- Generic "touch updated_at on row update" trigger, reused by every table
-- that has an updated_at column instead of repeating the same trigger body.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Generic BEFORE UPDATE trigger: stamps updated_at = now(). Attach per-table.';

-- Shared moderation/lifecycle status used by ads, comments, reports, etc.
-- Kept as a single enum rather than one-off text columns with ad-hoc CHECKs,
-- so moderation code has one vocabulary across tables.
create type public.moderation_status as enum (
  'active',
  'under_review',
  'removed',
  'shadow_limited'
);

-- account_status for profiles (section 24).
create type public.account_status as enum (
  'active',
  'suspended',
  'deleted'
);

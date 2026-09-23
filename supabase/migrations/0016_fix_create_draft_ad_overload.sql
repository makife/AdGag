-- ============================================================================
-- 0016_fix_create_draft_ad_overload.sql
-- Fixes a real bug found by running `supabase db push` against the live
-- project for the first time: `CREATE OR REPLACE FUNCTION` does NOT
-- collapse into a single object when a new parameter is added, even with
-- a default value — contrary to what earlier migrations' comments
-- claimed, it creates a SEPARATE overload.
--
-- 0005_ads.sql, 0009_ad_this_and_shares.sql and 0011_daily_challenges.sql
-- each added a trailing parameter to create_draft_ad(), assuming this
-- would replace the previous version. It didn't: three overloads ended up
-- coexisting —
--   create_draft_ad(p_subject_id, p_caption)
--   create_draft_ad(p_subject_id, p_caption, p_inspired_by_ad_id)
--   create_draft_ad(p_subject_id, p_caption, p_inspired_by_ad_id, p_daily_challenge_id)
-- — and PostgREST's RPC endpoint cannot disambiguate a call unless the
-- supplied parameter set exactly matches exactly one overload. Confirmed
-- live: calling with only {p_subject_id} returned "Could not choose the
-- best candidate function" even though all three overloads could
-- technically satisfy it. (The Flutter client always sends all four
-- parameter keys, so it was never actually broken by this in practice —
-- but any other caller supplying a subset would be, and three dead
-- overloads sitting in the schema is a real correctness/hygiene bug
-- regardless.)
--
-- 0005/0009/0011 are left untouched as an accurate historical record of
-- what actually ran — this migration fixes forward instead of rewriting
-- already-applied history.
-- ============================================================================

drop function if exists public.create_draft_ad(uuid, text);
drop function if exists public.create_draft_ad(uuid, text, uuid);

-- The 4-parameter version from 0011_daily_challenges.sql is now the sole
-- overload. Grants survive a DROP of a *different* overload, but restate
-- explicitly so intent isn't left implicit.
grant execute on function public.create_draft_ad(uuid, text, uuid, uuid) to authenticated;

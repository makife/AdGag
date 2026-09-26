-- Raise the Ad length cap from 10s to 30s (product decision, 2026-09-26):
-- one take of up to 30s, or several shorter takes stitched together in
-- the native editor. Mirrors VideoConstraints.max (Dart) and
-- MaxTotalDurationMs (native editor).
--
-- The upper bound has 1s of headroom over the 30s client cap on purpose:
-- duration_ms is written by the mux-webhook from Mux's own measured
-- duration, which can land a few ms above what the client exported
-- (container/encoder rounding). An exactly-30000 bound would fail a
-- legitimate 30s Ad into status 'failed' (see mux-webhook's error path).
alter table public.ads drop constraint duration_range;
alter table public.ads
  add constraint duration_range check (duration_ms is null or duration_ms between 1500 and 31000);

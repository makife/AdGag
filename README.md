# AdGag

**The social network where everything is an ad.**
_See it. Ad it. Go._

Internal codename in code/comments where the brand name would be premature to hardcode: `everything_is_an_ad`. See CLAUDE.md section 65 — the brand string itself (`AdGag`) is only used in UI copy/config, never baked into database or backend architecture.

This file is the living implementation record: architecture, decisions, setup, and phase status. It is kept in sync as phases land — see **Phase Status** at the bottom.

---

## 1. Architecture Overview

- **Client:** Flutter (feature-first structure), Riverpod (hand-written providers, no codegen), go_router.
- **Backend:** Supabase (Postgres + Auth + RLS + Edge Functions). Owns all social/application data.
- **Video:** A separate managed video provider (Mux, see §7) owns upload, transcoding, adaptive streaming and thumbnails. Supabase never proxies video bytes; the client uploads directly to the provider via a short-lived upload session minted by an Edge Function. See CLAUDE.md §18.
- **Contract boundary:** the Flutter app depends on repository interfaces (`FeedRepository`, `VideoService`, `AuthRepository`, ...), never directly on Supabase table shapes or the video vendor SDK, so either can evolve without a client rewrite (§59/§60).

## 2. Folder Structure

```
lib/
  core/            # cross-feature: theme, router, config, error types, supabase client, shared widgets
  shared/          # cross-feature models/widgets used by 2+ features
  features/
    auth/          # sign in/up, session
    feed/          # home feed
    create_ad/     # creation engine (record/import/trim/publish) — shared by AD, AD THIS, Daily Ad
    subjects/      # AdSubject pages, normalization
    daily_ad/      # Today's Ad challenge
    market/        # discovery/search
    profile/       # user profile
    social/        # follow system
    comments/      # REVIEWS
    notifications/ # ACTIVITY tab
    moderation/    # report/block
  each feature/    # data/ (repositories talking to Supabase) · domain/ (interfaces + models) · presentation/ (screens/providers/widgets)

supabase/
  migrations/      # numbered, forward-only SQL migrations (never hand-edit prod tables — §23)

l10n/              # ARB translation source (en, tr — §34)
env/               # per-environment --dart-define-from-file configs (git-ignored except *.example.json)
test/              # mirrors lib/ structure
```

## 3. ER Model (current + planned)

Tables actually migrated so far are marked **[done]**; the rest is the target shape from CLAUDE.md §23, recorded here so later migrations don't drift from the plan.

```
profiles [done]  ──┬─< follows [done] (follower_id, following_id)
                    ├─< ads [done] (user_id)
                    ├─< sold_reactions (user_id)
                    ├─< comments (user_id)
                    ├─< reports (reporter_id)
                    └─< blocks (blocker_id, blocked_id)

ad_subjects [done] ──┬─< ad_subject_aliases [done] (canonicalization — §10)
                      ├─< ad_subject_translations [done] (locale display names — §34)
                      └─< ads [done] (subject_id)

ads [done] ──┬─< sold_reactions (ad_id)          unique (user_id, ad_id)
      ├─< comments (ad_id)
      ├─< ad_views / analytics events (ad_id)
      ├─self inspired_by_ad_id [done, unused until Phase E's AD THIS UI] (AD THIS lineage — §9)
      └─> daily_challenges (daily_challenge_id, nullable — FK added when that table lands in Phase F)

daily_challenges ──< ads (daily_challenge_id)

notifications (recipient_id, actor_id, type, payload)
device_tokens (user_id, platform, token)
reports (target_type, target_id, reason, status)
```

## 4. SQL Migration Plan

| # | File | Phase | Contents |
|---|------|-------|----------|
| 0001 | `extensions_and_common.sql` | A | `pgcrypto`, shared `set_updated_at()` trigger fn, `moderation_status`/`account_status` enums |
| 0002 | `profiles_and_auth_trigger.sql` | A | `profiles` table, `handle_new_user()` trigger, RLS |
| 0003 | `follows.sql` | B | `follows` table, RLS (public read, self-only insert/delete) |
| 0004 | `ad_subjects.sql` | B | `ad_subjects`, `ad_subject_aliases`, `ad_subject_translations`, `canonicalize_subject_text()`, `get_or_create_ad_subject()` RPC |
| 0005 | `ads.sql` | B | `ads` (full target schema, §25), `ad_status`/`ad_visibility` enums, `create_draft_ad()`/`update_draft_ad()`/`delete_own_ad()` RPCs, `ads_count` sync trigger, feed indexes |
| 0006 | `video_pipeline.sql` | C | `video_webhook_events` idempotency log, `ads.video_asset_id` lookup index |
| 0007 | `sold_reactions.sql` | E | `sold_reactions`, `toggle_sold_reaction()` RPC (atomic press-again-to-remove), `ads.sold_count` sync trigger |
| 0008 | `comments.sql` | E | `comments` (REVIEWS), `create_comment()`/`delete_own_comment()` RPCs, `ads.comment_count` sync trigger |
| 0009 | `ad_this_and_shares.sql` | E | `create_draft_ad()` gains `p_inspired_by_ad_id` (AD THIS lineage), `ads.ad_this_count` sync trigger (counts only once the inspired Ad reaches `ready`), `increment_share_count()` RPC |
| 0010 | `feed_ranking.sql` | F | `get_feed_page()` RPC — the one place heuristic feed ranking lives (SOLD x3 + AD THIS x5 + comments, decayed by age), replacing pure freshness ordering |
| 0011 | `daily_challenges.sql` | F | `daily_challenges`, `get_current_daily_challenge()` (server-controlled time window, never trust device clock), `create_draft_ad()` gains `p_daily_challenge_id`, `ads.daily_challenge_id` FK finally wired up, participant-count sync trigger |
| 0012 | `reports_and_blocks.sql` | G | `reports`, `blocks`, `report_content()`/`block_user()`/`unblock_user()` RPCs, `is_blocked_either_way()` applied to `get_feed_page()` and REVIEWS visibility |
| 0013 | `rate_limiting.sql` | G | `rate_limit_events` + `enforce_rate_limit()`, wired into `create_comment`/`toggle_sold_reaction`/`create_draft_ad`/`report_content` and a `follows` insert trigger |
| 0014 | `notifications.sql` | H | `notifications`, `device_tokens`, triggers producing `new_follower`/`new_review`/`ad_this` notifications, `mark_notification_read()` RPC |
| 0015 | `analytics.sql` | H | `ad_events` (impression/play_started/two_second_view/completed/rewatched/shared/sold/ad_this), write-only from the client, batched inserts |

| 0016 | `fix_create_draft_ad_overload.sql` | — | Fixes a real bug found by pushing to a live project: 3 coexisting overloads of `create_draft_ad()` (see Verification log below) |
| 0017 | `fix_public_execute_grants.sql` | — | Fixes a more serious bug found the same way: every RPC was callable by anonymous callers because Postgres grants `EXECUTE` to `PUBLIC` by default and no migration had ever revoked it (see Verification log below) |

All 17 migrations are now applied to the real `diwxzyhwmcajyjbcfwhe` project — this is the full schema for the MVP scope in section 51, and it has been verified end-to-end against real Postgres, not just written.

Run migrations with the Supabase CLI once a project exists: `supabase db push` (or apply via the Supabase dashboard SQL editor for a quick start). Never hand-create tables in the dashboard outside a migration file (§23).

## 5. RLS Policy Plan

Established pattern (applied to `profiles`, to be repeated per table):

1. `enable row level security` + `force row level security`.
2. A `select` policy scoped to what should genuinely be public vs. owner-only vs. participant-only.
3. **No blanket insert/update/delete policy.** Every write path is either:
   - restricted to `auth.uid() = owner_column` (e.g. a user updating their own bio), or
   - denied entirely at the row-policy level and instead performed by a `SECURITY DEFINER` function/trigger (e.g. profile creation) or an Edge Function using the service role (e.g. webhook-driven status changes).
4. **Column-level `GRANT`/`REVOKE`** on top of row policies wherever a user may edit *some* but not *all* columns of their own row (e.g. a user can edit `display_name`/`bio` but never their own `account_status`). Postgres RLS alone is row-scoped, not column-scoped — this is the mechanism that actually prevents "users cannot modify counters directly" (§28).
5. Uniqueness that matters for abuse prevention (`sold_reactions(user_id, ad_id)`, `follows(follower_id, following_id)`) is a **database constraint**, not just an RLS check — RLS prevents forging *whose* row it is, the constraint prevents duplicates.

## 6. Video Upload / Playback Sequence (target — implemented in Phase C)

```
Flutter                Edge Function              Video Provider (Mux)         Supabase DB
   │  1. create draft ad (status=draft)  ───────────────────────────────────────▶│
   │  2. request upload session ▶│                                               │
   │                              │  3. create direct upload  ─────────────────▶│
   │                              │◀──────────── upload URL + asset id ──────────│
   │◀── upload URL ───────────────│                                               │
   │  4. PUT video bytes directly to provider (never through app server) ───────▶│
   │                                              5. transcode/generate thumb    │
   │                              │◀──────── 6. webhook: asset.ready ────────────│
   │                              │  7. verify signature, map asset→ad           │
   │                              │  8. update ad: status=ready, playback_id ───▶│
   │  9. ad now eligible for feed queries (status=ready) ◀───────────────────────│
```

Webhook handling is idempotent (keyed on provider asset id) and signature-verified (§43) — a POST merely *claiming* "video ready" without a valid signature is rejected.

**Implemented and deployed** (Phase C, deployed/verified in the Mux verification log below): `supabase/functions/create-upload-session` (steps 2-3 above — checks the caller owns the draft Ad, mints a Mux Direct Upload with `passthrough` set to the Ad id, marks the Ad `uploading`) and `supabase/functions/mux-webhook` (steps 6-8 — verifies the `Mux-Signature` HMAC, records the delivery in `video_webhook_events` before acting on it, updates the Ad to `ready`/`failed`/`processing`/`deleted` by event type). Step 4 (the client PUT) is `lib/core/video/dio_video_uploader.dart`; step 9 is `FeedRepository` only ever selecting `status = 'ready'`. Step 4 itself (an actual video file's bytes flowing through the Flutter app) is the one piece not yet verified against real infrastructure — see "What has NOT been verified" below.

**Deploying the functions** (already done for the `diwxzyhwmcajyjbcfwhe` project — this is the reference command for redeploying after a code change, or for a new environment):

```bash
supabase functions deploy create-upload-session
supabase functions deploy mux-webhook --no-verify-jwt   # see supabase/config.toml comment — Mux can't send a Supabase JWT

supabase secrets set MUX_TOKEN_ID=... MUX_TOKEN_SECRET=... MUX_WEBHOOK_SIGNING_SECRET=...
```

Then in the Mux dashboard, add a webhook endpoint pointing at `https://<project-ref>.supabase.co/functions/v1/mux-webhook` subscribed at least to `video.asset.ready`, `video.asset.errored`, and `video.asset.deleted`.

## 7. Feed Sequence (target — Phase F ranking, Phase C metadata)

```
Flutter FeedScreen → FeedRepository.fetchPage(cursor) → Postgres (candidate select:
  status = 'ready' AND not blocked-by-viewer AND published_at < cursor)
  → heuristic re-rank in the Edge Function/DB view (freshness, SOLD rate, AD THIS rate, ...)
  → page of Ad *metadata* (no video bytes) returned
  → client requests playback via VideoService.getPlaybackInfo(playbackId) → CDN HLS URL
  → bounded video-controller pool preloads N+1
```

`FeedRepository` is cursor-paginated from the start (§16) — no offset pagination is introduced even for the MVP heuristic ranking, so swapping in a real ranking service later doesn't change the client contract.

## 8. Technology Choices

| Concern | Choice | Why |
|---|---|---|
| State mgmt | `flutter_riverpod`, hand-written providers | No `build_runner`/codegen step required to run the app — verified as still actively maintained (2.6.x, Sept 2026) |
| Routing | `go_router` 14.x | Flutter-team maintained, `StatefulShellRoute` fits the 5-tab nav + deep link requirement (§33/§54) |
| Backend SDK | `supabase_flutter` 2.9.x | Official SDK, actively released (checked Sept 2026) |
| Camera | `camera` | First-party-adjacent, standard choice |
| Playback | `video_player` | First-party-adjacent; wrapped by a bounded controller pool in Phase C (§17) |
| Trim | `easy_video_editor` | Native trim without an FFmpeg dependency; updated as recently as June 2026 |
| Share sheet | `share_plus` | Standard for native share (§33) |
| Models | Hand-written immutable classes | Avoids a second codegen dependency (`freezed`) on top of Riverpod's; revisit if the model count outgrows hand-writing |
| Env config | `--dart-define-from-file` (JSON) | No secrets bundled as a plaintext asset in the app package; see §9 |

All package choices were checked against pub.dev for recent releases before being pinned — see chat history for sources. None are abandoned/tutorial-only packages.

**Video provider (Mux, recommended):** chosen over Cloudflare Stream for MVP because of simpler per-minute pricing predictability and a direct-upload flow that maps cleanly to the sequence in §6. The `VideoService` interface (Phase C) is provider-agnostic — switching to Cloudflare Stream later is a Edge Function change, not a client rewrite (§60).

## 9. Environment Configuration

Copy the example config for the environment you're running and fill in real values:

```
cp env/dev.example.json env/dev.json
```

Run with:

```
flutter run --dart-define-from-file=env/dev.json
```

Real `env/*.json` files are git-ignored (only `*.example.json` is committed). **No service-role key, video-provider secret, or webhook signing secret ever belongs in `env/`** — those are Supabase Edge Function secrets only (§27/§68).

## 10. Implementation Milestones

Following CLAUDE.md §52 DEVELOPMENT ORDER exactly:

- [x] **Phase A — Foundation:** Flutter scaffold, theming, routing + deep-link-ready shell, localization (en/tr), Supabase integration, email auth + session handling, `profiles` migration + RLS, unit tests for username rules.
- [x] **Phase B — Social Core:** `follows` (+ `FollowRepository`), `ad_subjects` with canonicalization/aliases/translations (+ `SubjectRepository`), full `ads` metadata schema with draft-lifecycle RPCs (+ `DraftAdRepository`), cursor-paginated `FeedRepository` (freshness-only ordering — heuristic ranking is Phase F), unit tests for row-mapping logic. No new screens this phase by design — feed/creation UI needs video (Phase C/D) to be meaningful; the data layer is ready for them.
- [x] **Phase C — Video:** `VideoService`/`VideoUploader` abstractions; `create-upload-session` + `mux-webhook` Edge Functions (signature verification, idempotency, ownership checks); `VideoControllerPool` (bounded, evicts outside the current+neighbor window); `FeedScreen` now a real vertical `PageView` of playable Ads (subject/creator overlay only — SOLD/REVIEWS/AD THIS are Phase E). Recording/import UI is still Phase D; this phase is the plumbing a recorded file flows through.
- [x] **Phase D — Creation:** one `CreateAdFlowController` state machine (subject -> capture -> trim-if-needed -> caption -> publish -> upload/processing status) driving `CreateAdScreen`; camera recording with a hard 10s auto-stop and a discard-if-under-1.5s guard; gallery import via `image_picker`; a deliberately minimal "pick where your 10s starts" trim step (`easy_video_editor`) shown only when a clip is too long; publish polls the Ad's status after upload since the draft->ready transition happens server-side (the webhook), not from any client call. Unit tests cover the state machine end to end with fake repositories (no camera/network needed).
- [x] **Phase E — Engagement:** SOLD (atomic toggle RPC, optimistic UI with server-truth reconciliation on next fetch), REVIEWS (paginated comments sheet, post/delete-own), AD THIS (`CreateAdFlowController.startAdThis` reuses the Phase D engine, lineage stored via `ads.inspired_by_ad_id`), external SHARE (`share_plus` + `increment_share_count`), AdSubject pages (`SOCK™` header, Trending/Top/New tabs, AD THIS SUBJECT, tap-through viewer). Design-system components added per section 64: `SoldButton`, `ReviewButton`, `AdThisButton`, `ShareButton`, `CreatorHeader`, `SubjectBadge`, `FeedActionRail`, `CountLabel`.
- [x] **Phase F — Discovery:** heuristic feed ranking (`get_feed_page()` — freshness + engagement, with an explicit note on its keyset-pagination-under-time-decay tradeoff); Market screen (Trending Subjects, Fresh Ads, Daily Ad banner, search entry); search over subjects and users (debounced); Daily Ad end-to-end (banner -> JOIN -> `CreateAdFlowController.startDailyChallenge` -> server-validated against the currently-active challenge). Also closed a gap the search feature exposed: there was no "view another user's profile" screen yet, so added `ProfileRepository`/`PublicProfileScreen` (section 13) with a FOLLOW button and Ads grid, reusing `SubjectAdsViewerScreen`'s tap-through pattern.
- [x] **Phase G — Safety:** report (Ad/user/comment) via `ReportSheet`, block/unblock (blocking auto-unfollows both directions), rate limiting on the five abuse vectors CLAUDE.md section 29 names explicitly. Block filtering is applied to the main feed and REVIEWS — **explicitly not yet** to subject pages, Market's Fresh Ads, profile Ads grids, or search (documented as a known gap in the migration itself, not silently assumed complete). No Flutter admin UI was built, per section 46 — moderation queue review is a Supabase-dashboard/future-internal-tool concern.
- [x] **Phase H — Polish:** notifications foundation (in-app ACTIVITY list, backed by triggers on follow/review/AD THIS; push *dispatch* deliberately not built — see "External Services" below, this needs real FCM/APNs credentials this environment doesn't have); `/ad/:id` deep link (`AdDetailScreen`) with the platform association-file setup documented below as the remaining external step; `ad_events` analytics wired into `AdVideoCard` (impression/play_started/two_second_view/completed/rewatched via a controller-position listener) and into SOLD/SHARE/AD THIS; a contextual "Think you can do better? Try AD THIS" hint after a few swipes (section 63). Performance/accessibility groundwork (bounded controller pool, cursor pagination everywhere, `Semantics` labels on custom buttons, 44px minimum tap targets) was built incrementally through earlier phases rather than as a separate pass — see each phase's entry above.

### All 8 phases (A–H) from CLAUDE.md section 52 are now implemented. `flutter analyze` and `flutter test` pass — see "Testing" below for exactly what that does and doesn't prove.

---

## Setup

### Prerequisites

1. **Flutter SDK** (stable channel, 3.47+ / Dart 3.13+). `flutter analyze` and `flutter test` now both pass clean against Flutter 3.47.5 — see "Verification log" below for what that did and didn't catch.
2. A [Supabase](https://supabase.com) project (free tier is fine for dev).
3. (Phase C) A [Mux](https://mux.com) account.
4. (Social login, optional for Phase A) Apple Developer account + Google Cloud OAuth client.

### First run

```bash
# 1. Generate native platform folders (not hand-written — see note below)
flutter create --org com.adgag --project-name adgag .

# 2. Install dependencies
flutter pub get

# 3. Configure environment
cp env/dev.example.json env/dev.json
# edit env/dev.json with your Supabase project URL + anon key
# (Project Settings → API in the Supabase dashboard)

# 4. Apply database migrations
# Install the Supabase CLI, then from the project root:
supabase link --project-ref YOUR_PROJECT_REF
supabase db push

# 5. (Phase C) Deploy Edge Functions + set video-provider secrets —
# see "Video Upload / Playback Sequence" above for the exact commands.

# 6. Run
flutter run --dart-define-from-file=env/dev.json

# 7. Verify
flutter analyze
flutter test
```

**After `flutter create .` (Phase D requirement): add camera/microphone/photo-library usage strings.** The `camera` and `image_picker` packages will crash at runtime without these — this is exactly the "external configuration" CLAUDE.md section 67 says to flag rather than skip:

- `ios/Runner/Info.plist`: add `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, and `NSPhotoLibraryUsageDescription` keys with user-facing strings explaining why AdGag needs each (e.g. "AdGag needs your camera to record Ads.").
- `android/app/src/main/AndroidManifest.xml`: add `<uses-permission android:name="android.permission.CAMERA" />` and `<uses-permission android:name="android.permission.RECORD_AUDIO" />`.

**Why `flutter create .` and not hand-written `android/`/`ios/` folders:** native platform scaffolding (Gradle files, `Info.plist`, Xcode project) is generated and kept correct by the Flutter tool itself and changes with each Flutter release. Hand-writing it here, without the SDK available to verify it builds, would be the highest-risk part of the codebase for the lowest benefit — `flutter create .` on an existing project only adds the missing platform folders and does not touch `lib/` or `pubspec.yaml`.

### Deep Links (Phase H)

Two different kinds of deep link, easy to conflate:

**1. Auth callback (email confirmation / OAuth redirect) — configured and working.** `supabase_flutter` listens for incoming deep links automatically via `app_links` (no Dart code needed — see `_handleIncomingLinks`/`_isAuthCallbackDeeplink` in its source, which detect an auth callback by the presence of auth-related query/fragment params, not by a specific scheme). The app registers a custom URL scheme, `adgag://login-callback`:
- Android: an `<intent-filter>` for `adgag://login-callback` in `android/app/src/main/AndroidManifest.xml` (alongside the launcher intent-filter — this file is hand-edited, not `flutter create .`-generated, and since `/android/` is gitignored, **this edit must be redone if the platform folder is ever regenerated from scratch** — see the note at the bottom of this section).
- iOS: a `CFBundleURLTypes` entry for the `adgag` scheme in `ios/Runner/Info.plist` (same regeneration caveat).
- Supabase project: `Authentication > URL Configuration` — Site URL and the redirect allow-list are set to `adgag://login-callback` (done via the Management API for the `diwxzyhwmcajyjbcfwhe` project; if you ever point this app at a different Supabase project, redo this in that project's dashboard or it'll default to `http://localhost:3000` and email confirmation links will appear to fail — though the confirmation itself still succeeds server-side before the broken redirect, since Supabase confirms the token first and redirects second).

**2. Universal/App Links for sharing** (`/ad/:id`, `/u/:username`, `/subjects/:id` — what `ShareButton` builds links to). `RoutePaths.adDetail`/`userProfile`/`subject` and `AdDetailScreen` etc. already handle the in-app routing once the OS hands a URL to the app, but this is a *separate* mechanism from the custom-scheme auth callback above, and still needs platform/hosting configuration outside this repo's scope:
- **iOS Universal Links**: host an `apple-app-site-association` file at `https://<APP_LINK_HOST>/.well-known/apple-app-site-association` (needs your Apple Team ID + bundle id) and add the associated domain capability in Xcode.
- **Android App Links**: host `https://<APP_LINK_HOST>/.well-known/assetlinks.json` (needs your app's SHA-256 signing certificate fingerprint) and add a *second*, separate `<intent-filter>` with `android:autoVerify="true"` for `https://<APP_LINK_HOST>/...` to `AndroidManifest.xml` — don't confuse this with the auth-callback intent-filter above.
- **Web fallback**: a simple landing page at `https://<APP_LINK_HOST>/ad/:id` for users without the app installed (App Store/Play Store redirect) — not part of this Flutter/Supabase codebase; needs separate static hosting.
- `EnvConfig.appLinkHost` (already wired) controls the host `ShareButton` builds links against per environment.

**Regenerating platform folders**: if you ever delete and rerun `flutter create .` (or set this project up fresh on another machine), both native edits in part 1 need to be reapplied by hand — they are not something any Flutter tooling regenerates automatically, unlike the launcher icon (`flutter_launcher_icons`) or the platform folders themselves.

### Push Notifications (Phase H)

The `notifications`/`device_tokens` tables and in-app ACTIVITY list are implemented and usable today without any of this. Actual push *delivery* needs:

| What | Where to get it | Notes |
|---|---|---|
| Firebase project + `google-services.json`/`GoogleService-Info.plist` | Firebase Console | Needed to add `firebase_messaging` to `pubspec.yaml` at all — not added yet, since it can't be verified without real config |
| APNs auth key (iOS) | Apple Developer → Keys | Uploaded to Firebase Cloud Messaging settings |
| A push-dispatch Edge Function | *(to be written)* | Reads `device_tokens`, calls FCM's HTTP v1 API using a service account, triggered by the same events that already write to `notifications` (section 32) |

Deliberately not implemented speculatively: a `firebase_messaging` integration written against invented config would be broken code, not working code, in this environment.

### What I need from you (§67 — external services)

| Credential | Where to get it | Goes in | Status |
|---|---|---|---|
| Supabase project URL + anon/publishable key | Supabase dashboard → Project Settings → API | `env/dev.json` (and staging/prod equivalents) | ✅ configured (dev) |
| Supabase service role key | Same page — **never** put this in `env/` | Used only transiently for admin API test calls this session; never stored in any file | n/a — not needed by app code |
| Mux access token + secret | Mux dashboard → Settings → Access Tokens | Supabase Edge Function secrets | ✅ set, verified live |
| Mux webhook signing secret | Mux dashboard → Settings → Webhooks | Supabase Edge Function secrets | ✅ set, verified live |
| Apple Services ID + key (Sign in with Apple) | Apple Developer → Certificates, IDs & Profiles | Supabase Auth provider config + `sign_in_with_apple` native setup (before App Store submission — see note in `auth_repository_impl.dart`) | not provided |
| Google OAuth client ID (Android/iOS/Web) | Google Cloud Console → APIs & Services → Credentials | Supabase Auth provider config | not provided |
| Apple Team ID + app signing cert fingerprint | Apple Developer / Android signing config | Deep link association files (above) | not provided |
| Firebase project + APNs key | Firebase Console / Apple Developer | Push notifications (above) | not provided |

Nothing above blocks continued implementation — every phase proceeded without them; the remaining rows are only needed for social login and push/deep-link delivery specifically.

## Testing

```bash
flutter analyze
flutter test
```

Both commands pass clean as of the verification below. 14 test files cover pure-Dart logic across every phase: username/video-constraint validation, row-mapping for every domain model, DB-enum-to-Dart-enum mappings (username/ad_status/report_reason/ad_event_type/notification_type — a mismatch in any of these silently breaks the corresponding feature with a Postgres cast error), Mux URL builders, and the full creation-flow state machine exercised end-to-end against fake repositories.

### What HAS been verified against real infrastructure (not just statically)

- **The full SQL schema** (17 migrations) applied cleanly to a real hosted Postgres 17.6 project via `supabase db push`, and was then exercised end-to-end through real HTTP calls (signup → `handle_new_user` trigger → profile row → sign-in → `get_or_create_ad_subject` → `create_draft_ad` → RLS draft-invisible-to-anon → `toggle_sold_reaction` business-rule rejection → `delete_own_ad` → account deletion cascade), all against the actual `diwxzyhwmcajyjbcfwhe` project, then cleaned up. See the Verification log below for the two real bugs this surfaced and fixed.
- **Both Edge Functions are deployed and have been invoked against the real project**, both statically (`deno check`) and at runtime: `create-upload-session` made a real call to the Mux API and got back a real, valid Direct Upload URL; `mux-webhook` correctly processed a cryptographically-signed `video.asset.ready` event end to end (ad transitioned to `ready` with correct `playback_id`/`thumbnail_url`/`duration_ms`), rejected a replayed duplicate, an invalid signature, a missing signature, and an expired (10-minute-old) timestamp — see the Verification log below. Mux also appears to have called the webhook for real on its own (an unplanned second, UUID-shaped event id showed up in the idempotency log that this session never generated), suggesting the webhook registration itself is live and correctly signature-verified against genuine Mux traffic, not just synthetic test payloads.
- **`flutter build web`** succeeds — a full dart2js/wasm-dry-run compile of all 121+ lib files against the real Supabase config, not just `flutter analyze`'s type-checking.
- **`flutter build apk --debug`** succeeds — a real Android build (`app-debug.apk`, ~166MB), the first native platform build of this app that's ever completed. See the Verification log below for what it took to get there (disk space + a stale build cache + a genuine new native-toolchain dependency, all resolved).
- The Flutter app is configured against the real project (`env/dev.json`, gitignored, never committed) using the publishable key — see "Environments" above.
- **Installed and launched on a real Android device**, which surfaced and got two real bugs fixed that no amount of static analysis could have caught — see the Verification log below ("real-device testing") for the full detail: a `SafeArea`/bottom-inset layout bug hiding the creation flow's action buttons behind the system gesture-nav bar, and a PostgREST `PGRST201` relationship-ambiguity error on the home feed once `sold_reactions` gave `ads`→`profiles` two possible join paths.

### What has NOT been verified — still needs a real device, external service, or your input

- **No real video was ever uploaded through the pipeline.** `create-upload-session` was proven to talk to Mux correctly, and `mux-webhook` was proven to process a `video.asset.ready` event correctly — but no actual video file was PUT to a Mux upload URL and processed by Mux itself (no `ffmpeg` and very little free disk space in this environment to generate/hold a test file). The two halves are each verified against real infrastructure separately; the full round trip (record → upload → Mux transcodes → real webhook fires → ready) has not been, even though camera recording itself now works on a real device (see below).
- **The two real-device bug fixes (SafeArea layout, `PGRST201` embed ambiguity) have not yet been re-verified on-device** — they're fixed, analyzed, tested, and rebuilt into a new APK, but need a reinstall + retest to confirm on the hardware that originally surfaced them.
- **iOS is completely unverified** — no Mac/Xcode in this environment; the `ios/` folder was generated by `flutter create .` but never built.
- **No widget tests exist**, only pure logic tests — a screen can pass `flutter analyze`/`flutter build web` and still throw at first render on a real device (a bad `Consumer` scope, a permission dialog interaction, etc.).
- **Apple/Google OAuth and Firebase/APNs are entirely unconfigured** — see "External Services" below.

Treat those as the next verification milestones, in roughly that order of risk.

### Verification log (2026, Flutter 3.47.5 / Dart 3.13.4)

First real `flutter pub get` against this codebase surfaced two dependency pins that were simply wrong — version numbers that had never been checked against an actual pub.dev resolve:
- `easy_video_editor: ^1.1.0` — that version never existed; real releases top out at 0.1.6 (still a healthy package: pub score 160/160, actively maintained — only the version number was wrong). Fixed to `^0.1.6`.
- `intl: ^0.19.0` — incompatible with the `flutter_localizations` version shipped by this Flutter SDK, which requires `^0.20.3`. Fixed accordingly.

`flutter analyze` then caught several real bugs static reading alone had missed:
- `AppException`'s `cause` was declared as a named super parameter but every subclass forwarded it positionally — fixed by making it positional on the base class (nothing referenced it by name anywhere, so this was a pure bug fix, not a behavior change).
- `app_theme.dart` used `CupertinoPageTransitionsBuilder` without importing `package:flutter/cupertino.dart` — `material.dart` does not re-export it.
- Six `FutureProvider.family(...)` declarations were typed as `FutureProvider<T>` when `.family` actually returns `FutureProviderFamily<T, Arg>` — a real type error in `feed_providers.dart`, `profile_providers.dart`, `social_providers.dart` (×3), and `subject_providers.dart` (×2).
- A missing `currentUserIdProvider` import in `public_profile_screen.dart`.
- `supabase_flutter` 2.17 deprecated `Supabase.initialize`'s `anonKey` parameter in favor of `publishableKey`.

`flutter test` then passed all 59 test cases with no further changes needed.

### Verification log — real Supabase project connected (2026)

Installed the Supabase CLI (`npm install -g supabase`, v2.117.0) and Deno (`npm install -g deno`, v2.9.6 — needed to type-check the Edge Functions, a runtime `flutter analyze` never touches). Authenticated with a user-provided personal access token (session-only, never written to any file) and linked the existing `AdGag` project (ref `diwxzyhwmcajyjbcfwhe`, Postgres 17.6, eu-west-1).

**`deno check` on both Edge Functions passed clean** against their real `npm:@supabase/supabase-js@2` dependency — first validation they've ever had.

**`supabase db push` applied all 15 migrations to the real, empty project with no errors** — the schema (extensions, RLS, triggers, RPCs) had never executed against real Postgres before this. Then probed the live API with `curl` (not just trusting a clean push), which found two real bugs static review had missed entirely:

1. **`create_draft_ad` had three coexisting overloads.** `CREATE OR REPLACE FUNCTION` does not collapse into one object when a parameter is added, even with a default — contrary to what this repo's own migration comments claimed. 0005/0009/0011 each added a trailing parameter, leaving three overloads live; PostgREST's RPC endpoint couldn't disambiguate a call unless it supplied exactly one overload's parameter set (confirmed: a 1-arg call failed with "Could not choose the best candidate function"). Fixed in `0016_fix_create_draft_ad_overload.sql` by dropping the two superseded overloads.

2. **Every SECURITY DEFINER function was callable by a completely anonymous caller.** PostgreSQL grants `EXECUTE` to the `PUBLIC` pseudo-role by default on every new function; every migration's `grant ... to authenticated` was purely additive on top of that and never actually restricted anything. Confirmed live: an anonymous request to `create_draft_ad()` reached the function body and failed on an internal `NOT NULL` constraint rather than being rejected for lacking a grant. This affected every mutating RPC across every phase — reports, blocks, comments, SOLD, ads, everything. Fixed in `0017_fix_public_execute_grants.sql`: revoked `PUBLIC` execute on all 12 authenticated-required RPCs and all trigger-only/internal-helper functions, added an explicit `auth.uid() is null` guard to each authenticated RPC, and caught one near-miss before pushing — `is_blocked_either_way()` is called from `get_feed_page()` (`SECURITY INVOKER`, not `DEFINER`) and from the `comments_select_visible` RLS policy, both of which run as the actual caller, so revoking it from `anon`/`authenticated` would have silently broken the feed and REVIEWS for every real user. Kept it callable there with a documented, accepted minor tradeoff (see the migration's comments).

Re-verified end to end with a throwaway test account after both fixes: anonymous calls to every mutating RPC now cleanly rejected at the grant level (`42501 permission denied`, not a leaked constraint error); `get_feed_page`/`is_blocked_either_way` still work anonymously; full authenticated flow (signup → `handle_new_user` trigger → profile created → sign-in → `get_or_create_ad_subject` → `create_draft_ad` → RLS correctly hides the draft from anon → `toggle_sold_reaction` cleanly rejects with "Ad is not available" on a non-ready ad → `delete_own_ad`) all worked correctly against the real database, then the test user was deleted (cascade to profile confirmed) and no test data was left behind.

**Configured the Flutter app against this real project**: `env/dev.json` (gitignored, confirmed via `git check-ignore`) with the project URL and the new-style `sb_publishable_...` key — matching the `publishableKey` parameter fixed in the dependency-resolution pass above, not the legacy anon JWT.

**Generated the native platform folders** (`flutter create --org com.adgag --project-name adgag .`) — they hadn't existed before this. Deleted the auto-generated `test/widget_test.dart` (the generic counter-app template, references a `MyApp` widget that doesn't exist in this codebase). Re-ran `flutter analyze`/`flutter test`: still clean, 59/59.

**`flutter build web --dart-define-from-file=env/dev.json` succeeded** — a real dart2js compile of the entire app against the real backend config, not just static analysis. Two non-blocking warnings, both worth knowing about but neither a bug in this repo's code: a wasm-compatibility lint inside `easy_video_editor`'s own web platform-channel source (only matters if a future `--wasm` web build is needed), and a `CupertinoIcons` font-asset notice (the app doesn't use any Cupertino icon glyphs, only `CupertinoPageTransitionsBuilder` for transition behavior, so this is a no-op tree-shake case, not a missing dependency).

### Verification log — real Android debug APK built (2026)

`flutter build apk --debug` initially failed twice on the machine's `C:` drive being effectively full (as low as 0.00GB free at one point mid-build). Per explicit approval, deleted exactly the previously-identified safe/regenerable dev caches — `.gradle/caches`, `.gradle/wrapper`, `.gradle/daemon`, `npm-cache`, `Pub/Cache`, the Deno cache — freeing **11.1GB**, nothing else touched (no personal files, no project source, no Android SDK components, no other projects). A lingering Gradle daemon process from the earlier failed attempt was stopped first so it wouldn't hold file locks on the caches being deleted.

Retrying then surfaced two more real, distinct issues, each fixed in turn:
- A stale/corrupted incremental build state from the earlier interrupted attempt caused a Gradle `mergeDebugAssets` failure ("new files were found... process may still be writing"). Fixed with `flutter clean` — the project's own generated `build/` directory, always fully regenerable, not a disk-space cleanup.
- `easy_video_editor` has native/JNI Android code requiring **CMake 3.22.1**, not yet installed — a genuine new SDK-tool dependency this project actually needs, not a misconfiguration. Once enough disk headroom existed, the Gradle/AGP toolchain installed it automatically on the next build.

**Final build succeeded**: `build\app\outputs\flutter-apk\app-debug.apk`, ~166MB (normal for an unminified debug build). `flutter analyze`: 0 issues. `flutter test`: 59/59. This is the first time any native platform build of this app has actually completed.

Also set up real branding for this build: `assets/branding/AdGagIkon.png` (icon-only mark) now generates the actual Android/iOS/web/Windows/macOS launcher icons via `flutter_launcher_icons` (replacing Flutter's default template icon), and `assets/branding/AdGag.png` (full lockup: icon + wordmark + tagline) is now shown as a real image on the splash screen and the onboarding screen's brand-name slide, rather than approximating the wordmark with a `TextStyle`/`ShaderMask`.

**Still not verified at that point**: the APK had not been installed/launched on an actual device or emulator — only compiled. iOS remains completely unverified (no Mac/Xcode here).

### Verification log — Mux connected, Edge Functions deployed and runtime-tested (2026)

You provided a Mux access token/secret and webhook signing secret for the "AdGag Development" Mux environment. Set as Supabase secrets (`supabase secrets set`, values never written to any file, confirmed afterwards via `supabase secrets list` which only ever returns hashes) and deployed both functions (`supabase functions deploy create-upload-session`, `supabase functions deploy mux-webhook --no-verify-jwt`).

No `ffmpeg` is available in this environment and disk space is very tight, so a full real-video round trip (PUT actual bytes to Mux, wait for Mux to transcode, wait for a real `video.asset.ready` delivery) wasn't attempted. Instead, verified each half against real infrastructure separately, using a throwaway test account created and deleted the same way as the schema verification above:

- **`create-upload-session`**: called it for real, authenticated, against an owned draft Ad. It made a real call to the Mux API and returned a genuine, valid Mux Direct Upload URL (`https://direct-uploads-....mux.com/upload/...`), and correctly updated the Ad's `status` to `uploading` and `video_provider` to `mux`. This proves the Mux token/secret are valid and the function's Mux integration works, independent of whether any bytes ever get uploaded.
- **`mux-webhook`**: constructed a `video.asset.ready` payload by hand and signed it with the real webhook secret using the exact scheme Mux uses (`HMAC-SHA256` over `"{timestamp}.{rawBody}"`, sent as `Mux-Signature: t=...,v1=...`) — this exercises the identical code path a genuine Mux delivery would, just with a synthetic body. Result: the Ad correctly transitioned to `status: ready` with `playback_id`, `thumbnail_url` (correctly constructed as `https://image.mux.com/{playback_id}/thumbnail.jpg?time=0`), `duration_ms` (7.5s → 7500, correctly converted), and `published_at` all set correctly. Then verified every rejection path: resending the identical event returned "Already processed" (200, not reprocessed); an invalid signature, a missing signature, and a signature computed with a 10-minute-old timestamp were all rejected with 401.
- **Unplanned bonus signal**: the idempotency log (`video_webhook_events`, readable only via admin access — confirmed anon genuinely cannot read it, which is correct by design) contained a second event with a UUID-shaped id this session never generated, timestamped right around when `create-upload-session` was called. The most likely explanation is Mux itself fired a real webhook (e.g. for upload-session creation) that our deployed function received, correctly verified against a genuine Mux signature, and handled gracefully via the "unhandled event type, no-op" path — evidence the webhook registration is live end to end against real Mux traffic, not just this session's synthetic tests.

All test data (auth user, profile via cascade, draft Ad, Ad subjects) was deleted afterward and confirmed empty via direct table counts; the 2-row webhook idempotency log was left as-is (no PII, not client-readable, legitimate operational bookkeeping rather than test pollution).

### Verification log — real-device testing found two real bugs (2026)

The Android debug APK was installed and used on a real physical device for the first time. This surfaced two bugs neither `flutter analyze`, `flutter test`, nor any of the earlier build/schema verification could have caught, since both only manifest against real runtime conditions (a physical device's system UI, and PostgREST's live relationship-cache resolution):

1. **Creation-flow action buttons rendered under the system gesture-nav bar, effectively unreachable.** `camera_record_view.dart`'s record button, `trim_step.dart`'s "Use this clip", and `caption_publish_step.dart`'s "Publish" were all positioned relative to the bottom of the screen with no `SafeArea`/bottom-inset handling — `Scaffold` does not add this automatically for `body`. On a device using gesture navigation, the buttons sat behind or under the system nav area. Fixed: `trim_step.dart` and `caption_publish_step.dart` now wrap `body` in `SafeArea`; `camera_record_view.dart`'s `Positioned` bottom offset now adds `MediaQuery.paddingOf(context).bottom` on top of its existing spacing (its camera preview stays full-bleed — only the control column needed the inset).
2. **`PGRST201` on the home feed: "Could not embed because more than one relationship was found for 'ads' and 'profiles'."** Reproduced live via `curl` against the real project before fixing (HTTP 300, exact error text matching what the user saw on-device), and confirmed fixed the same way afterward (HTTP 200). Root cause: once `sold_reactions` existed with FKs to both `ads` and `profiles`, PostgREST could no longer resolve a plain `profiles(...)` embed on `ads` — it now saw two paths, the direct `ads_user_id_fkey` and an indirect many-to-many one through `sold_reactions`. This pattern was reused in four repositories (`feed_repository_impl.dart`'s `getById`, `subject_repository_impl.dart`, `market_repository_impl.dart`, `profile_repository_impl.dart`); all four were fixed by disambiguating to `profiles!ads_user_id_fkey(username)`, matching PostgREST's own suggested-fix hint exactly.

`flutter analyze`: 0 issues. `flutter test`: 59/59. Rebuilt `app-debug.apk` with both fixes.

**Lesson for future schema changes**: any new table that FKs to both `ads` and `profiles` (e.g. a future `ad_battles`/`battle_votes` per CLAUDE.md section 47) will reintroduce this same `PGRST201` ambiguity for any *other* plain `profiles(...)` embed added on `ads` later — always use an explicit `!fk_name` embed on `ads` going forward, not just where it's already broken.

**A third, self-inflicted bug immediately followed**: the rebuild above was run as plain `flutter build apk --debug`, without `--dart-define-from-file=env/dev.json`. `EnvConfig.assertConfigured()` correctly throws when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty, but it throws inside `main()` before `runApp()` — so Flutter never paints a first frame, and the app just shows Android's default white window background forever. The user reported exactly this ("opens to a white page, stays there") on installing that build. Fixed by rebuilding with `flutter build apk --debug --dart-define-from-file=env/dev.json`.

APK file size turned out to be an unreliable way to confirm this (an early check assumed a size match meant the flag was applied — wrong; size varies for unrelated reasons like normal code changes between builds, not `--dart-define` values, which are just a handful of short strings). The reliable check used afterward: `flutter build apk --debug`'s debug output isn't AOT-compiled, so the Dart kernel is shipped as a plain asset — `unzip -p app-debug.apk assets/flutter_assets/kernel_blob.bin | grep -c "<the real supabase url>"` returns a real match count when the dart-defines were actually baked in, and 0 when they weren't. This is the check to use whenever there's doubt about whether a debug APK has real config, not the file size.

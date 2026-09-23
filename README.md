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

**Implemented** (Phase C): `supabase/functions/create-upload-session` (steps 2-3 above — checks the caller owns the draft Ad, mints a Mux Direct Upload with `passthrough` set to the Ad id, marks the Ad `uploading`) and `supabase/functions/mux-webhook` (steps 6-8 — verifies the `Mux-Signature` HMAC, records the delivery in `video_webhook_events` before acting on it, updates the Ad to `ready`/`failed`/`processing`/`deleted` by event type). Step 4 (the client PUT) is `lib/core/video/dio_video_uploader.dart`; step 9 is `FeedRepository` only ever selecting `status = 'ready'`.

**Deploying the functions:**

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

`RoutePaths.adDetail`/`userProfile`/`subject` and `AdDetailScreen` etc. already handle the in-app routing once the OS hands a URL to the app. What's still missing is entirely platform/hosting configuration outside this repo's scope:

- **iOS Universal Links**: host an `apple-app-site-association` file at `https://<APP_LINK_HOST>/.well-known/apple-app-site-association` (needs your Apple Team ID + bundle id) and add the associated domain capability in Xcode.
- **Android App Links**: host `https://<APP_LINK_HOST>/.well-known/assetlinks.json` (needs your app's SHA-256 signing certificate fingerprint) and add an `<intent-filter>` with `android:autoVerify="true"` to `AndroidManifest.xml`.
- **Web fallback**: a simple landing page at `https://<APP_LINK_HOST>/ad/:id` for users without the app installed (App Store/Play Store redirect) — not part of this Flutter/Supabase codebase; needs separate static hosting.
- `EnvConfig.appLinkHost` (already wired) controls the host `ShareButton` builds links against per environment.

### Push Notifications (Phase H)

The `notifications`/`device_tokens` tables and in-app ACTIVITY list are implemented and usable today without any of this. Actual push *delivery* needs:

| What | Where to get it | Notes |
|---|---|---|
| Firebase project + `google-services.json`/`GoogleService-Info.plist` | Firebase Console | Needed to add `firebase_messaging` to `pubspec.yaml` at all — not added yet, since it can't be verified without real config |
| APNs auth key (iOS) | Apple Developer → Keys | Uploaded to Firebase Cloud Messaging settings |
| A push-dispatch Edge Function | *(to be written)* | Reads `device_tokens`, calls FCM's HTTP v1 API using a service account, triggered by the same events that already write to `notifications` (section 32) |

Deliberately not implemented speculatively: a `firebase_messaging` integration written against invented config would be broken code, not working code, in this environment.

### What I need from you (§67 — external services)

| Credential | Where to get it | Goes in |
|---|---|---|
| Supabase project URL + anon key | Supabase dashboard → Project Settings → API | `env/dev.json` (and staging/prod equivalents) |
| Supabase service role key | Same page — **never** put this in `env/` | Supabase Edge Function secrets only (Phase C's upload-session function) |
| Mux access token + secret | Mux dashboard → Settings → Access Tokens | Supabase Edge Function secrets (Phase C) |
| Mux webhook signing secret | Mux dashboard → Settings → Webhooks | Supabase Edge Function secrets (Phase C) |
| Apple Services ID + key (Sign in with Apple) | Apple Developer → Certificates, IDs & Profiles | Supabase Auth provider config + `sign_in_with_apple` native setup (before App Store submission — see note in `auth_repository_impl.dart`) |
| Google OAuth client ID (Android/iOS/Web) | Google Cloud Console → APIs & Services → Credentials | Supabase Auth provider config |
| Apple Team ID + app signing cert fingerprint | Apple Developer / Android signing config | Deep link association files (above) |
| Firebase project + APNs key | Firebase Console / Apple Developer | Push notifications (above) |

Nothing above blocks continued implementation — every phase proceeded without them; they're only needed to actually run the app against a live backend and to enable push/deep-link delivery specifically.

## Testing

```bash
flutter analyze
flutter test
```

Both commands pass clean as of the verification below. 14 test files cover pure-Dart logic across every phase: username/video-constraint validation, row-mapping for every domain model, DB-enum-to-Dart-enum mappings (username/ad_status/report_reason/ad_event_type/notification_type — a mismatch in any of these silently breaks the corresponding feature with a Postgres cast error), Mux URL builders, and the full creation-flow state machine exercised end-to-end against fake repositories.

### What HAS been verified against real infrastructure (not just statically)

- **The full SQL schema** (17 migrations) applied cleanly to a real hosted Postgres 17.6 project via `supabase db push`, and was then exercised end-to-end through real HTTP calls (signup → `handle_new_user` trigger → profile row → sign-in → `get_or_create_ad_subject` → `create_draft_ad` → RLS draft-invisible-to-anon → `toggle_sold_reaction` business-rule rejection → `delete_own_ad` → account deletion cascade), all against the actual `diwxzyhwmcajyjbcfwhe` project, then cleaned up. See the Verification log below for the two real bugs this surfaced and fixed.
- **Both Edge Functions type-check** (`deno check`) against their real npm dependencies (`@supabase/supabase-js`) — the first validation they've ever had, in a completely different toolchain than Flutter's.
- **`flutter build web`** succeeds — a full dart2js/wasm-dry-run compile of all 121+ lib files against the real Supabase config, not just `flutter analyze`'s type-checking.
- The Flutter app is configured against the real project (`env/dev.json`, gitignored, never committed) using the publishable key — see "Environments" above.

### What has NOT been verified — still needs a real device, external service, or your input

- **Edge Functions have never been deployed or invoked.** `deno check` proves they compile; it proves nothing about runtime behavior (the Mux API call, webhook signature verification against a real Mux delivery, etc.). Deployment is intentionally blocked on Mux credentials — see "External Services" below for exactly what's needed.
- **No physical device or emulator run.** `camera_record_view.dart`, the upload pipeline, and anything touching platform channels (camera, video_player, permission_handler) have never executed on an actual Android/iOS device or emulator — only compiled for web. `flutter build apk --debug` was attempted and failed on low disk space (2.3GB free), not a code issue — see the Verification log below.
- **iOS is completely unverified** — no Mac/Xcode in this environment; the `ios/` folder was generated by `flutter create .` but never built.
- **No widget tests exist**, only pure logic tests — a screen can pass `flutter analyze`/`flutter build web` and still throw at first render on a real device (a bad `Consumer` scope, a permission dialog interaction, etc.).
- **Mux, Apple/Google OAuth, and Firebase/APNs are entirely unconfigured** — see "External Services" below.

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

**Deliberately not done, per explicit instruction**: Edge Function deployment. `supabase functions list` / `supabase secrets list` against the real project both confirm nothing is deployed and no secrets are set. Deploying `create-upload-session` and `mux-webhook` needs `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`, and `MUX_WEBHOOK_SIGNING_SECRET` first (see "External Services" above) — stopped here rather than deploying code that would fail at runtime with unconfigured secrets.

**Attempted, blocked by environment, not code**: `flutter build apk --debug` failed after ~9 minutes — not a build error, but the machine's `C:` drive being at 100% capacity (2.3GB free of 238GB) while Gradle tried to download the Android NDK (~2.6GB). This needs disk space freed on the machine, not a code fix; `flutter build web` above already gives real full-compile verification in the meantime.

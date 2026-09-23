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
| — | *(later)* | F–H | `ad_views`, `daily_challenges` (+ FK back onto `ads.daily_challenge_id`), `reports`, `blocks`, `notifications`, `device_tokens` |

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
- [ ] **Phase F — Discovery:** Market, search, Daily Ad, heuristic ranking.
- [ ] **Phase G — Safety:** reports, blocks, moderation status, rate limiting.
- [ ] **Phase H — Polish:** notifications, deep links end-to-end, analytics, performance pass, accessibility, onboarding polish.

---

## Setup

### Prerequisites

1. **Flutter SDK** (stable channel, 3.47+ / Dart 3.13+) — **not installed in this dev environment**; install it yourself and run the steps below. Until then, this codebase has been written carefully but **not compiled or run** — treat it as reviewed-but-unverified.
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

### What I need from you (§67 — external services)

| Credential | Where to get it | Goes in |
|---|---|---|
| Supabase project URL + anon key | Supabase dashboard → Project Settings → API | `env/dev.json` (and staging/prod equivalents) |
| Supabase service role key | Same page — **never** put this in `env/` | Supabase Edge Function secrets only, when Phase C adds the upload-session function |
| Mux access token + secret | Mux dashboard → Settings → Access Tokens | Supabase Edge Function secrets (Phase C) |
| Mux webhook signing secret | Mux dashboard → Settings → Webhooks | Supabase Edge Function secrets (Phase C) |
| Apple Services ID + key (Sign in with Apple) | Apple Developer → Certificates, IDs & Profiles | Supabase Auth provider config + `sign_in_with_apple` native setup (before App Store submission — see note in `auth_repository_impl.dart`) |
| Google OAuth client ID (Android/iOS/Web) | Google Cloud Console → APIs & Services → Credentials | Supabase Auth provider config |

Nothing above blocks continued implementation — Phases B onward proceed without them; they're only needed to actually run the app against a live backend.

## Testing

```bash
flutter analyze
flutter test
```

No test has been run in this session (Flutter SDK unavailable here). `test/core/username_validator_test.dart` and `test/features/auth/app_user_test.dart` cover the pure-Dart logic written in Phase A; run them once the SDK is installed and treat any failure as a real bug to fix, not a false positive.

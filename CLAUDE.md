# MASTER PRODUCT & DEVELOPMENT PROMPT

You are the lead product architect, senior Flutter engineer, backend
architect, UI/UX designer, and security-minded technical lead for a new
global mobile social network.

Your task is not to create a quick demo or a generic TikTok clone.

Design and implement a production-minded MVP with a clean architecture
that can evolve into a large global platform without premature
overengineering.

The product concept is:

# \[APP NAME\]

## "The social network where everything is an ad."

The temporary internal project name may be `everything_is_an_ad` until
the final brand name is selected.

------------------------------------------------------------------------

# 1. PRODUCT VISION

This is a short-form creative social network where users make very short
"advertisements" about literally anything.

The content does NOT have to be a real commercial advertisement. The
advertisement format itself is the creative medium.

Users can advertise themselves, a sock, a rock, coffee, their cat, their
husband/wife, their profession, their city, Monday, sleep, being single,
friendship, rain, homework, an idea, a feeling, a completely imaginary
product, and eventually real commercial products and brands.

Example:

A woman holds her husband's dirty sock dramatically in front of the
camera.

Title: `SOCK™`

Voice-over: "Throw it at the enemy. It kills."

Ending: `MY HUSBAND'S SOCKS™`

The joke is that an ordinary object is being presented as if it were a
professionally marketed product.

Other examples:

`ROCK™` --- "Some people are harder."

`MONDAY™` --- "Nobody asked for it. We made it anyway."

`ME™` --- "32 years in development. Still in beta."

This tone defines the product.

The platform should encourage creativity, parody, humor, storytelling,
performance, cinematography and clever advertising language.

The fundamental user prompt is:

> Pick something. Sell it in 10 seconds.

The product must NOT gradually become a generic short-video social
network. Every major feature should reinforce the advertising metaphor.

------------------------------------------------------------------------

# 2. CORE BRAND PHILOSOPHY

Primary slogan:

# "The social network where everything is an ad."

Supporting phrases can include:

-   "Anything. Literally."
-   "What are you selling today?"
-   "See it. Ad it. Sell it."
-   "Pick something. Sell it in 10 seconds."
-   "Everything deserves an ad."
-   "Make anything worth buying."
-   "Don't just post it. Advertise it."

Use these sparingly.

The app should have a confident, playful, clever personality.

Do NOT make the UI childish. Do NOT make it look like an advertising
agency dashboard. Do NOT make it look like an e-commerce marketplace.

It is a consumer entertainment/social platform.

The word "sell" is metaphorical unless a future commercial feature
explicitly involves a real product.

------------------------------------------------------------------------

# 3. CONTENT MODEL

Every uploaded short video is called an `Ad`.

Every Ad belongs to a subject/topic. Internally call this entity
`AdSubject`.

Examples: ROCK, SOCK, MONDAY, COFFEE, MY DAD, MARRIAGE, RAIN, ME.

Multiple users can advertise the same subject.

This is fundamental.

For example, `SOCK™` may eventually contain 84,291 Ads.

Users should be able to tap the subject and browse all Ads created for
SOCK.

This is NOT merely a hashtag system. The AdSubject is a first-class
entity in the database and product.

------------------------------------------------------------------------

# 4. VIDEO RULES

For MVP, maximum duration is 10 seconds. Minimum duration should be
configurable, initially around 2 seconds.

Vertical video preferred: 9:16.

The recording experience must communicate the 10-second limitation
clearly.

Allow: - camera recording - importing from gallery - trimming - simple
text overlay - simple voice-over if practical - optional music/audio
architecture

Do NOT build a CapCut clone.

Editing must remain intentionally lightweight. The goal is: idea →
record → publish, with minimal friction.

Architect the editor so additional capabilities can later be added
without rewriting the entire creation flow.

------------------------------------------------------------------------

# 5. MAIN NAVIGATION

Use a bottom navigation architecture appropriate for a video-first
application.

Recommended conceptual structure:

1.  HOME / FEED
2.  MARKET / DISCOVER
3.  AD --- central creation action
4.  ACTIVITY
5.  PROFILE

The central creation button should visually stand out. Avoid a generic
"+" if possible. Use `AD` or an equivalent branded creation control.

Navigation naming may evolve, so keep labels configurable/localizable.

------------------------------------------------------------------------

# 6. HOME --- AD FEED

The app opens directly into a fullscreen vertical video feed.

The interaction should feel immediate. One video occupies the screen.
Swipe vertically to move between Ads.

Overlay should include: - AdSubject name, e.g. `SOCK™` - Creator,
e.g. `@username` - Optional caption - SOLD - REVIEWS - SHARE - AD THIS -
FOLLOW when appropriate

Do not blindly copy TikTok visual placement. Design an original but
familiar short-video interaction model.

------------------------------------------------------------------------

# 7. SOLD

Instead of conceptually centering the product around a generic "Like",
use `SOLD`.

A user pressing SOLD means: "This ad sold me."

It is functionally similar to a like/reaction, but branded around the
product concept.

Each user may SOLD an Ad only once. Pressing again removes it.

Display counts such as `12.8K SOLD`.

Avoid confusing users into thinking a financial transaction occurred.
Onboarding should subtly explain the metaphor.

------------------------------------------------------------------------

# 8. REVIEWS

Comments can be branded as `REVIEWS`.

Users can comment on Ads. Backend entity can remain `comments`.

Support create, delete own, pagination, report and moderation. Replies
may be implemented if architecture remains clean, but deep nested
comment trees are not necessary for MVP.

------------------------------------------------------------------------

# 9. AD THIS --- CRITICAL FEATURE

This is one of the defining mechanics.

When a user watches an Ad and thinks "I can make a better/funnier
version of this," they press `AD THIS`.

If the current AdSubject is SOCK, pressing AD THIS should open creation
with subject=SOCK preselected.

The loop is:

SEE IT → AD IT → PUBLISH → OTHER PEOPLE SEE IT → THEY AD IT

Track this relationship.

Ads should optionally contain `inspired_by_ad_id`.

This allows future features such as chains, remix trees, origin
attribution, "Inspired by" and challenge propagation.

Do NOT implement complex trees visually in MVP unless needed, but
preserve the data relationship.

------------------------------------------------------------------------

# 10. AD SUBJECT PAGE

Every AdSubject has its own page.

Example:

# SOCK™

84.2K Ads

Sections/tabs: - Trending - Top - New

Potential later section: Battles.

Display videos associated with the subject and allow `AD THIS SUBJECT`.

Search should discover subjects.

Subjects must support canonicalization to avoid uncontrolled
duplication. Example: Sock, SOCK, socks, Socks should not automatically
become four unrelated global subjects.

Design a normalization/alias strategy. However, do NOT over-normalize
creative custom subjects such as `MY HUSBAND'S SOCKS`, which may
intentionally be distinct.

------------------------------------------------------------------------

# 11. DAILY AD

Create a global daily creative challenge.

Example:

TODAY'S AD

ROCK 🪨

"Sell it in 10 seconds."

Users participate using the same creation system.

A Daily Challenge contains: - id - subject - start time - end time -
title - prompt - optional image/icon - status - participant count

Ads submitted to it store `daily_challenge_id`.

After the challenge ends, rankings can include Top, Trending and Most
SOLD. Eventually support `AD OF THE DAY`.

Do not make popularity solely dependent on raw total likes; architecture
should support normalized ranking based on views and engagement.

Daily challenge time boundaries should be server-controlled, not
device-controlled. For MVP, a single UTC-based global challenge day is
acceptable if communicated consistently.

------------------------------------------------------------------------

# 12. MARKET / DISCOVERY

The discovery section can be branded `MARKET`.

This is NOT a commerce marketplace. It is the market of ideas/Ads.

Possible sections: - Trending Subjects - Best Ads - Fresh Ads - Daily
Ad - Rising Creators - Subjects You May Like

Search must support users and subjects, and eventually hashtags if
introduced.

Keep search extensible.

------------------------------------------------------------------------

# 13. PROFILE

Profile includes: - avatar - username - display name - bio - follower
count - following count - Ads - SOLD received - Total views

Possible achievements later: - Ad of the Day wins - Battle wins - Top
Ad - Total shares

Include a profile video grid/list. Allow users to pin Ads later.

------------------------------------------------------------------------

# 14. AD ME

Preserve the original concept of users advertising themselves.

Each user can eventually have a special `ME™` / `AD ME` video. This acts
as a 10-second personal commercial.

This should NOT turn the whole platform into LinkedIn, a dating app or a
CV platform.

AD ME is one creative use of the larger system.

For MVP this can simply be an Ad whose subject is associated with the
creator's self-profile, or it can be added shortly after MVP. Design the
schema so it is possible.

------------------------------------------------------------------------

# 15. FOLLOW SYSTEM

Implement follow, unfollow, followers and following.

Feed architecture should later support `For You` and `Following`. MVP
may default to For You.

Prevent duplicate follow records using database constraints.

------------------------------------------------------------------------

# 16. FEED ARCHITECTURE

Do NOT simply fetch all Ads ordered by created_at.

Build a feed service abstraction.

MVP ranking can use heuristic signals such as: - freshness - completion
rate - SOLD rate - rewatch rate - share rate - comment/review rate - AD
THIS rate - creator relationship - subject affinity

AD THIS is a particularly strong signal. A video that causes other
people to create content is valuable.

Do NOT create a machine-learning recommendation engine yet.

Create clean interfaces so the ranking implementation can later be
replaced.

Use cursor-based pagination. Avoid offset pagination for large feed
tables.

Feed responses should contain metadata, NOT video bytes.

------------------------------------------------------------------------

# 17. VIDEO PLAYBACK EXPERIENCE

Feed performance is critical.

When video N is playing: - N+1 should be preloaded/buffered. -
Potentially prepare N+2 metadata or initial segments. - Do NOT preload
dozens of full videos. - Keep previous content temporarily cached.

Release player resources intelligently.

Flutter implementation should avoid creating an unlimited number of
active video controllers. Build a bounded player/controller pool.

Pause playback immediately when: - app goes background - feed item loses
visibility - another media surface becomes active

Resume intelligently. Respect mute/audio state.

Design for Wi-Fi, 4G/5G and poor mobile networks.

Track startup latency and buffering.

------------------------------------------------------------------------

# 18. VIDEO DELIVERY ARCHITECTURE

Do NOT tightly couple the product to Supabase Storage.

Create a video provider abstraction.

For development/MVP, choose a managed video solution capable of: -
direct upload - transcoding - adaptive streaming - thumbnail
generation - CDN delivery - webhooks

Examples of the category include managed video platforms such as
Cloudflare Stream or Mux.

Do not hardcode business logic around a single provider.

Create an interface such as `VideoService` with responsibilities such
as: - createUploadSession() - getPlaybackInfo() - deleteAsset() -
verifyWebhook() - getThumbnail()

Conceptual flow:

Flutter ↓ authenticated backend function ↓ request upload session ↓
video provider returns secure direct-upload URL ↓ Flutter uploads
directly ↓ video provider processes/transcodes ↓ provider webhook ↓
backend verifies webhook ↓ ad status becomes READY ↓ video becomes
eligible for feed

The video file should NOT pass through the primary application API
server.

------------------------------------------------------------------------

# 19. VIDEO STATES

Ads must have explicit processing states:

draft uploading processing ready failed blocked deleted

Only READY Ads appear in normal feeds.

If processing fails, show the user a recoverable error.

Create cleanup strategy for abandoned uploads/drafts.

------------------------------------------------------------------------

# 20. ADAPTIVE STREAMING

Design for adaptive streaming. Prefer HLS where supported by the
selected video platform.

Potential qualities: 480p, 720p, 1080p.

Do not force 1080p on poor connections. Optimize for
time-to-first-frame, not maximum resolution.

------------------------------------------------------------------------

# 21. FLUTTER ARCHITECTURE

Use current stable Flutter/Dart practices.

Before selecting exact packages, verify they are actively maintained and
appropriate. Do not use abandoned packages simply because they appear in
old tutorials.

Use a feature-first project structure, conceptually:

lib/ core/ shared/ features/ auth/ feed/ create_ad/ subjects/ daily_ad/
market/ profile/ social/ comments/ notifications/ moderation/

Separate presentation, domain/business logic and data/infrastructure
without creating unnecessary enterprise boilerplate.

Use a sensible state management solution. Riverpod is acceptable if
appropriate.

Routing should support deep links. Keep platform-specific integrations
behind abstractions.

------------------------------------------------------------------------

# 22. BACKEND --- SUPABASE

Use Supabase as the primary MVP backend.

Use: - Supabase Auth - PostgreSQL - Row Level Security - Realtime
selectively - Edge Functions where appropriate

Do not use Realtime everywhere. Most feed data can use normal
requests/caching.

Supabase should own social/application data. Video provider should own
video processing/delivery.

------------------------------------------------------------------------

# 23. DATABASE DESIGN

Create proper migrations. Never rely on manually created production
tables.

Use UUIDs where appropriate.

Core entities should include at minimum: - profiles - ads -
ad_subjects - ad_subject_aliases if needed - sold_reactions - comments -
follows - ad_views or analytics event architecture - daily_challenges -
reports - blocks - notifications - device_tokens

Potential future entities: - ad_battles - battle_votes -
brand_challenges - challenge_entries - achievements - creator_stats

Do NOT implement all future systems now, but avoid schema choices that
make them impossible.

------------------------------------------------------------------------

# 24. PROFILES

Conceptual fields:

id username display_name avatar_url bio created_at updated_at
account_status

Username must be unique and normalized. Define username rules.

Do not trust client-side validation alone.

------------------------------------------------------------------------

# 25. ADS

Conceptual fields:

id user_id subject_id caption video_provider video_asset_id playback_id
thumbnail_url duration_ms status inspired_by_ad_id daily_challenge_id
visibility created_at published_at deleted_at

Counters may include:

view_count sold_count comment_count share_count ad_this_count

Be thoughtful about counter architecture.

Do not naïvely perform hot-row updates for every high-volume event
forever.

For MVP simple counters may be acceptable, but isolate the mechanism so
aggregation can later move to queues/event processing.

------------------------------------------------------------------------

# 26. VIEWS / ANALYTICS

A swipe past a video should NOT automatically equal a meaningful view.

Define events such as: - impression - play_started - 2_second_view -
completed - rewatched - shared - sold - ad_this

Do not send excessive network requests for every millisecond. Batch
analytics where practical.

For recommendation quality, collect watch duration, completion, rewatch
and skip timing while respecting privacy and applicable laws.

Do not build invasive tracking.

------------------------------------------------------------------------

# 27. AUTH

Support an extensible authentication layer.

MVP options: - Apple - Google - email

Apple sign-in must be correctly handled for iOS where required.

Do not expose service-role credentials in Flutter. Never place secrets
in client source code.

------------------------------------------------------------------------

# 28. RLS AND SECURITY

This is mandatory.

Enable Row Level Security for exposed Supabase tables.

Policies should ensure: - users edit only their own profiles where
appropriate - users create/delete only their own Ads - users cannot
forge SOLD records for another user - users cannot modify counters
directly - users cannot create follows as another user -
moderation/admin operations are protected - private/internal fields are
not exposed unnecessarily

Do not trust user_id sent by client when it can be derived from
authenticated identity.

Use unique constraints for `(user_id, ad_id)` SOLD and
`(follower_id, following_id)` follows.

------------------------------------------------------------------------

# 29. RATE LIMITING / ABUSE

Plan protection for: - comment spam - follow spam - SOLD spam - upload
spam - report abuse - username enumeration - automated scraping where
practical

Sensitive actions should be server-mediated or rate limited.

Do not assume RLS alone solves abuse.

------------------------------------------------------------------------

# 30. CONTENT MODERATION

Because this is user-generated video, moderation is not optional.

Build report flows from day one.

Report reasons may include: - nudity/sexual content - violence -
hate/harassment - bullying - dangerous activity - spam/scam -
copyright - impersonation - other

Users must be able to report an Ad, report a user and block a user.

Blocked users should disappear appropriately from each other's
experiences.

Design moderation status fields and keep integration points for external
moderation services.

------------------------------------------------------------------------

# 31. PRODUCT SAFETY

The concept encourages users to "advertise anything."

Do NOT encourage harassment of identifiable private individuals,
humiliating people without consent, dangerous stunts, illegal products,
sexual exploitation or hate content.

Humor can be edgy, but product mechanics must support reporting,
blocking and moderation.

------------------------------------------------------------------------

# 32. NOTIFICATIONS

Support architecture for: - new follower - SOLD milestone if useful -
comment/review - reply - Daily Ad - Ad This attribution - challenge
result - moderation/system notification

Do not spam users. Implement notification preferences.

Use FCM/APNs through an appropriate push architecture. Store device
tokens securely.

------------------------------------------------------------------------

# 33. SHARE / VIRAL LOOP

External sharing is important.

Users should be able to share Ads through the native share sheet to
services such as Instagram, TikTok, WhatsApp, Messages and other
installed apps.

Shared content should preserve tasteful attribution.

Potential watermark:

\[APP NAME\] @username

Do not create an obnoxious watermark.

Support deep links:

shared Ad → app installed: open Ad → not installed: web landing/App
Store/Play Store path

Architect universal links/app links.

------------------------------------------------------------------------

# 34. LOCALIZATION

This is intended to be global.

Do not hardcode English UI strings throughout widgets.

Implement localization from the beginning.

Initial languages: - English - Turkish

Architecture should support many more.

User-generated content must NOT be automatically translated unless
explicitly designed.

AdSubject localization is tricky. A canonical subject may have localized
display names.

Example: canonical concept: SOCK Turkish: ÇORAP English: SOCK

Design for this possibility without overbuilding an ontology.

------------------------------------------------------------------------

# 35. UI / VISUAL IDENTITY

The UI should feel: - modern - premium - bold - minimal - playful -
creator-focused

NOT: - corporate advertising software - cheap meme app - children's
game - TikTok clone - e-commerce marketplace

Video must dominate the feed.

UI overlays should be visually restrained.

The advertising metaphor should appear in terminology and subtle graphic
details.

Consider tasteful typography inspired by advertising/editorial design.

Avoid excessive gradients and unnecessary glassmorphism.

Support dark mode and light mode. Dark mode may be the primary
video-feed presentation.

Ensure accessibility: contrast, tap targets, screen reader labels,
reduced motion where possible, captions/text alternatives where
relevant.

------------------------------------------------------------------------

# 36. ONBOARDING

Keep onboarding short.

Potential sequence:

Screen 1: \[APP NAME\] "The social network where everything is an ad."

Screen 2: "Pick anything." Show: rock, coffee, yourself, Monday.

Screen 3: "Sell it in 10 seconds."

Screen 4: "See it. Ad it. Sell it."

Then authentication/account creation.

Do not force users through a long tutorial. Teach AD THIS and SOLD
contextually.

------------------------------------------------------------------------

# 37. EMPTY STATES

Empty states must reinforce the brand.

Examples:

No Ads for a subject: "No one's sold this yet." CTA: "Be the first to
advertise it."

No posts on profile: "Nothing for sale yet."

Creation draft failed: "This one didn't make the campaign."

Use humor sparingly. Error messages must remain understandable.

------------------------------------------------------------------------

# 38. CREATION FLOW

Recommended flow:

Tap AD ↓ choose/type subject ↓ record/import video ↓ trim/edit ↓ caption
↓ preview ↓ publish ↓ upload progress ↓ processing ↓ ready

For AD THIS:

Tap AD THIS ↓ subject already selected ↓ record ↓ publish

For Daily Ad:

Daily challenge ↓ JOIN ↓ subject already selected ↓ record ↓ publish

Reuse the same creation engine. Do not create three independent upload
implementations.

------------------------------------------------------------------------

# 39. UPLOAD RESILIENCE

Mobile networks fail.

Uploads should: - show progress - support cancellation - handle
temporary connection loss gracefully - retry intelligently - avoid
duplicate Ad creation - retain local draft when possible

Use idempotency where appropriate.

Do not publish an Ad until video processing succeeds.

------------------------------------------------------------------------

# 40. OFFLINE / POOR CONNECTION BEHAVIOR

Full offline social functionality is not required.

Cached current/previous content should fail gracefully. Show useful
offline state. Do not freeze the UI.

Upload drafts should survive reasonable interruptions.

------------------------------------------------------------------------

# 41. PERFORMANCE

Target smooth scrolling on mid-range Android devices, not only flagship
iPhones.

Avoid: - rebuilding entire feed unnecessarily - keeping many video
controllers alive - unbounded memory caches - loading full-resolution
thumbnails unnecessarily - blocking main UI isolate with expensive
processing

Profile performance. Use lazy loading. Use image/video caching
carefully.

------------------------------------------------------------------------

# 42. BACKEND FUNCTION RESPONSIBILITIES

Use Edge Functions/server-side functions for operations that require
trust or external secrets.

Examples: - create video upload session - video webhook - moderation
integrations - push notification dispatch - sensitive ranking
operations - admin operations - future payment/brand challenge logic

Do NOT put video transcoding itself inside a short-lived Edge Function.

Heavy media processing belongs to the managed video provider or
dedicated workers.

------------------------------------------------------------------------

# 43. VIDEO WEBHOOK SECURITY

When the video provider reports asset ready, asset failed or asset
deleted, verify webhook signatures.

Never trust arbitrary public requests claiming "video ready."

Map provider asset ID to the correct Ad.

Ensure webhook handling is idempotent.

------------------------------------------------------------------------

# 44. DELETION

Deleting an Ad should: - remove/hide it immediately from feeds - mark
database state appropriately - trigger video asset deletion where
applicable - handle comments/reactions according to retention policy

Avoid broken references.

Account deletion must eventually support proper user-data deletion
workflows required by app stores and applicable privacy laws.

------------------------------------------------------------------------

# 45. PRIVACY

Prepare: - Privacy Policy - Terms - Community Guidelines

The application handles accounts, user-generated videos, social
relationships and engagement analytics.

Collect only data actually needed.

Do not expose emails publicly.

Do not put private profile data into public API responses.

------------------------------------------------------------------------

# 46. ADMIN / MODERATION

Do not build a huge admin dashboard in Flutter.

Create a minimal internal moderation/admin strategy.

Admins need eventually to: - review reports - remove Ads - suspend
accounts - restore content - manage Daily Ad - inspect moderation
history

Admin privileges must NEVER be determined by a client-controlled
boolean.

Use secure roles/claims/server validation.

------------------------------------------------------------------------

# 47. FUTURE --- AD BATTLES

Do NOT prioritize this over the core feed.

Design for future: two users advertise the same subject and the
community chooses the stronger/funnier Ad.

Potential entities: - ad_battles - battle_entries - battle_votes

Possible profile stat: Battle Wins.

Do not build this until core creation/feed retention is validated.

------------------------------------------------------------------------

# 48. FUTURE --- BRAND CHALLENGES

Eventually real brands may create sponsored challenges.

Example:

"Advertise our drink in 10 seconds."

Creators submit Ads. Potential prizes.

This is future monetization.

Architect clear distinction between organic AdSubject and sponsored
Brand Challenge.

Paid/sponsored content must be clearly labeled. Never disguise paid
advertising as organic user content.

Do NOT implement brand billing/payment infrastructure in MVP.

------------------------------------------------------------------------

# 49. MONETIZATION PHILOSOPHY

Do not damage early growth with aggressive interstitial advertising.

Possible future revenue: - sponsored Ad challenges - brand creator
competitions - promoted subjects - creator tools - premium editing
capabilities - brand analytics - carefully integrated advertising

The unique commercial advantage is that advertising itself is part of
the content format.

Preserve user trust. Sponsored content must be identifiable.

------------------------------------------------------------------------

# 50. METRICS

Instrument the MVP to understand whether the idea works.

Important metrics: - DAU / MAU - D1 retention - D7 retention - D30
retention later - Ads created per active creator - percentage of viewers
who create an Ad - AD THIS conversion rate - Daily Ad participation -
average watch completion - rewatch rate - SOLD/view ratio - share/view
ratio - comments/view - subject page → create conversion - time from
install → first Ad - upload failure rate - video startup latency -
buffering rate

The north-star candidate should focus on meaningful creative
participation, not merely passive video views.

A useful metric may be `Weekly Active Advertisers`: users who publish at
least one legitimate Ad during the week.

------------------------------------------------------------------------

# 51. MVP SCOPE

Do NOT build everything described above immediately.

PHASE 1 must focus on proving the behavior.

Required MVP: - Authentication - Profile - Fullscreen vertical feed -
10-second video recording/import - Video upload - Managed video
processing/CDN - AdSubject creation/selection - Publish Ad - SOLD -
Reviews/comments - Follow/unfollow - AD THIS - Subject pages - Daily
Ad - Basic Market/discovery - Search - Notifications foundation -
Report/block - Basic moderation - External share - Analytics
foundation - Localization foundation - Deep-link foundation

Everything else can wait.

------------------------------------------------------------------------

# 52. DEVELOPMENT ORDER

Implement in disciplined phases.

## PHASE A --- Foundation

Flutter project, environment configuration, routing, state management,
theme, localization, Supabase integration, authentication, database
migrations, RLS.

## PHASE B --- Social Core

profiles, follows, subjects, basic feed metadata.

## PHASE C --- Video

video provider abstraction, direct upload, processing webhook, playback,
preloading, upload state.

## PHASE D --- Creation

camera/gallery, 10-second constraint, subject selection, caption,
publish, draft/error handling.

## PHASE E --- Engagement

SOLD, reviews, AD THIS, sharing, subject pages.

## PHASE F --- Discovery

Market, search, Daily Ad, basic ranking.

## PHASE G --- Safety

reports, blocks, moderation, rate limits.

## PHASE H --- Polish

notifications, deep links, analytics, performance, accessibility, error
handling, onboarding.

Do not jump randomly between features.

------------------------------------------------------------------------

# 53. TESTING

Write tests for critical business logic.

At minimum: - authentication state - RLS assumptions/integration - SOLD
uniqueness - follow uniqueness - subject normalization - feed
pagination - upload state machine - webhook idempotency - AD THIS
attribution - Daily Ad eligibility - block behavior

Use unit tests where appropriate. Use widget tests for important Flutter
flows. Create integration tests for critical paths.

Critical path:

signup → feed → create Ad → upload → processing → ready → playback →
SOLD → AD THIS

------------------------------------------------------------------------

# 54. ENVIRONMENTS

Support: - development - staging - production

Do not hardcode production endpoints.

Use environment configuration.

Separate Supabase/video provider environments where practical.

Never commit secrets.

Provide `.env.example` containing variable names only.

------------------------------------------------------------------------

# 55. OBSERVABILITY

Add structured logging.

Track: - Flutter crashes - API failures - upload failures - video
processing failures - playback failures - webhook failures

Do not log passwords, auth tokens or sensitive personal data.

Architecture should support crash reporting services later.

------------------------------------------------------------------------

# 56. CODE QUALITY

Do not generate a giant monolithic codebase.

Do not put all logic inside widgets.

Do not put SQL logic randomly throughout Flutter.

Do not duplicate models unnecessarily.

Use typed models.

Use consistent error handling.

Document unusual architectural decisions.

Avoid abstractions that serve no current or plausible near-term purpose.

Prefer boring, understandable code.

------------------------------------------------------------------------

# 57. DATABASE PERFORMANCE

Add indexes intentionally.

Likely examples: - ads(status, published_at) - ads(user_id,
published_at) - ads(subject_id, published_at) - comments(ad_id,
created_at) - sold_reactions(ad_id) - follows(follower_id) -
follows(following_id) - daily challenge lookup

Do not create indexes blindly.

Use cursor pagination.

Avoid N+1 queries.

Do not fetch entire profiles or comment histories for every feed item.

------------------------------------------------------------------------

# 58. COUNTERS

Counts displayed frequently --- views, SOLD, reviews, followers,
following, Ads --- should not require expensive COUNT(\*) operations on
every feed request.

Use appropriate maintained counters/materialized aggregates when needed.

For MVP keep implementation understandable.

Design an upgrade path for asynchronous/event-based aggregation at
scale.

------------------------------------------------------------------------

# 59. FEED SCALE EVOLUTION

MVP: Postgres-based candidate selection + heuristic ranking.

Growth stage: precomputed candidate pools, cached feeds, event
aggregation.

Large scale: dedicated recommendation infrastructure, event streaming,
feature store/ranking models if justified.

Do NOT build large-scale infrastructure before traffic requires it.

Keep the Flutter client dependent on a stable FeedRepository/API
contract rather than SQL assumptions.

------------------------------------------------------------------------

# 60. VIDEO SCALE EVOLUTION

MVP: managed video platform.

Growth: optimize encoding profiles, CDN/cache behavior, upload path and
cost controls.

Large scale: evaluate provider economics, multi-CDN/object
storage/custom processing only if financially justified.

The application should not need a rewrite when video infrastructure
changes.

------------------------------------------------------------------------

# 61. PRODUCT PRINCIPLES

Whenever deciding whether to add a feature, ask:

Does this make creating Ads more fun?

Does this make discovering creative Ads better?

Does this encourage one Ad to create another?

Does this strengthen the "everything is an ad" identity?

If not, question whether the feature belongs.

Do not blindly copy Stories, livestreams, DMs, streaks, shopping or long
videos just because other social networks have them.

------------------------------------------------------------------------

# 62. MOST IMPORTANT PRODUCT LOOP

Protect this loop above everything:

USER OPENS APP ↓ SEES A FUNNY/SMART AD ↓ THINKS "I CAN DO THIS" ↓
PRESSES AD THIS ↓ CREATES A 10-SECOND AD ↓ PUBLISHES ↓ OTHERS WATCH ↓
SOLD / REVIEW / SHARE ↓ SOMEONE ELSE PRESSES AD THIS ↓ NEW CONTENT IS
CREATED

This is the viral creative loop.

The product succeeds if watching causes creating.

------------------------------------------------------------------------

# 63. FIRST-TIME USER EXPERIENCE

A new user should understand the app within seconds.

Possible first feed experience:

Video: ROCK™

Creator presents a rock dramatically.

Overlay: "Some people are harder."

Below: SOLD, REVIEWS, AD THIS.

After several swipes, subtly surface:

"Think you can do better?"

AD THIS.

The UI itself should teach the concept.

------------------------------------------------------------------------

# 64. DESIGN SYSTEM

Create reusable components/tokens for: - spacing - typography - radius -
elevation - animation duration - icons - buttons - video overlays -
avatars - subject badges

Avoid random one-off styling.

Build sensible equivalents of: - AdVideoCard - CreatorHeader -
SubjectBadge - SoldButton - ReviewButton - AdThisButton -
VideoProgress - FeedActionRail

Do not prematurely create dozens of generic components.

------------------------------------------------------------------------

# 65. BRAND PLACEHOLDER

Do NOT permanently name the product ADME or ADUP.

Those names may conflict with existing products/brands.

Use a configurable placeholder `[APP NAME]` or internal codename.

All brand strings should be easy to replace globally.

Do not hardcode the final brand name into database architecture.

------------------------------------------------------------------------

# 66. INITIAL DELIVERABLES

Before blindly writing hundreds of files, produce:

1.  concise architecture overview
2.  folder structure
3.  database ER model
4.  SQL migration plan
5.  RLS policy plan
6.  video upload/playback sequence
7.  feed sequence
8.  technology/package choices with reasoning
9.  environment configuration plan
10. implementation milestones

Then begin implementation.

Do not stop at the planning document unless explicitly asked.

Proceed phase by phase.

After each phase: - run analyzer/linter - run tests - fix errors -
document what was completed - identify any required credentials or
external configuration

Do not claim something works if it has not been tested.

------------------------------------------------------------------------

# 67. EXTERNAL SERVICES

Whenever an external service requires API keys, Supabase configuration,
video-provider account, Apple configuration, Google configuration or
push certificates, do not invent values.

Create placeholders and clearly tell me exactly: - what I need - where I
obtain it - where it must be inserted

Continue implementing everything that does not require the missing
secret.

Do not block the entire project because one credential is unavailable.

------------------------------------------------------------------------

# 68. IMPORTANT ENGINEERING RULE

Never solve a problem by weakening security.

Examples:

Do not disable RLS because an insert fails.

Do not expose Supabase service role to Flutter.

Do not make video upload endpoints unauthenticated merely for
convenience.

Do not trust client counters.

Do not accept arbitrary user IDs for authenticated actions.

Fix the architecture instead.

------------------------------------------------------------------------

# 69. IMPORTANT PRODUCT RULE

Never allow generic social-network features to dilute the core concept.

This is NOT:

"TikTok but another app."

It is:

# THE SOCIAL NETWORK WHERE EVERYTHING IS AN AD.

The content primitive is not simply VIDEO. It is AD.

The organizing primitive is not simply HASHTAG. It is AD SUBJECT.

The primary positive reaction is SOLD.

The remix mechanic is AD THIS.

The daily challenge is TODAY'S AD.

Discovery is MARKET.

The user's special self-introduction can be AD ME.

These concepts should make the product recognizable even if the logo is
hidden.

------------------------------------------------------------------------

# 70. FINAL PRODUCT TEST

At every major milestone ask:

Could this exact interface belong to any generic short-video app?

If YES, strengthen the unique product identity.

But do not sacrifice usability merely to be different.

Users should immediately understand watch, swipe, react, comment and
create while gradually learning SOLD, AD THIS, AD SUBJECT and DAILY AD.

------------------------------------------------------------------------

# 71. LONG-TERM VISION

If the concept succeeds, the platform may eventually contain: - millions
of creators - millions of AdSubjects - hundreds of millions of Ads -
real brand challenges - creator competitions - professional creators -
comedy - cinematography - music - personal branding - cultural trends

A random object on someone's desk should be capable of becoming
tomorrow's global creative challenge.

The platform's fundamental cultural behavior should become:

Someone sees something ordinary and thinks:

"I could make an ad for that."

That behavior is the product.

------------------------------------------------------------------------

# 72. START NOW

Begin by auditing the current repository if one already exists.

Do not destroy existing working code.

If the repository is empty, initialize the project using the
architecture above.

First output the proposed implementation architecture and dependency
choices.

Then create the foundation.

Work iteratively and keep the application runnable after each major
phase.

Prioritize correctness, security, maintainability, performance and
simple UX over unnecessary complexity.

The MVP must feel polished, fast and intentional.

The ultimate product promise is:

# \[APP NAME\]

## The social network where everything is an ad.

### Pick something. Sell it in 10 seconds.

---

# IMPLEMENTATION CHECKPOINT (2026-09-23)

**This section is a living status record, appended after the product spec above — it does not modify sections 1-72.** Future sessions: update *this* section going forward rather than adding a new one; check it against actual repo/infra state (`git log`, `supabase migration list --linked`, `flutter test`) before trusting it, since it can drift out of date.

Repo: `C:\Users\LENOVO10OCT2020\Desktop\makifbilgisayar\AdGag`, brand name **AdGag** (codename `everything_is_an_ad` retired — the real name was decided). 14 commits, 124 `lib/` files, 14 test files (59 test cases), 17 SQL migrations, 2 Supabase Edge Functions. Full narrative detail for all of this lives in `README.md` (architecture, ER model, RLS plan, tech choices, and — most importantly — the "Verification log" entries, which are the authoritative record of what's actually been proven against real infrastructure vs. only written).

## Status: all 8 development-order phases (section 52) implemented

Phases A through H are done — auth, social graph, video pipeline, creation flow, engagement (SOLD/REVIEWS/AD THIS/share/subject pages), discovery/ranking, safety (reports/blocks/rate-limiting), and polish (notifications/deep-link target/analytics/onboarding hint). See the per-phase git commits and README's "Implementation Milestones" section for what shipped in each.

## What's been verified against REAL infrastructure (not just written/statically checked)

- **Supabase project is real and connected**: project `AdGag`, ref `diwxzyhwmcajyjbcfwhe`, eu-west-1, Postgres 17.6. All 17 migrations applied via `supabase db push`. `env/dev.json` (gitignored, already configured — don't need to redo) points the Flutter app at it using the `sb_publishable_...` key.
- **Two real bugs were found and fixed by actually running the schema against live Postgres** (static review had missed both):
  1. `CREATE OR REPLACE FUNCTION` does **not** collapse into one object when a parameter is added, even with a default — it creates a new overload. `create_draft_ad` ended up with 3 coexisting overloads across migrations 0005/0009/0011, breaking PostgREST's RPC resolution. Fixed in `0016_fix_create_draft_ad_overload.sql`. **Lesson for any future migration that changes an RPC's parameter list: either match the existing signature exactly, or explicitly `DROP FUNCTION` the old signature.**
  2. **PostgreSQL grants `EXECUTE` to `PUBLIC` by default on every new function.** Every RPC's `grant ... to authenticated` was purely additive and never actually restricted anon access — confirmed live, an anonymous caller reached `create_draft_ad`'s body. Fixed in `0017_fix_public_execute_grants.sql` (explicit `REVOKE ... FROM PUBLIC` + an `auth.uid() is null` guard on every authenticated-required RPC). **Lesson: every future `SECURITY DEFINER` RPC must explicitly revoke `PUBLIC` execute, or it's accessible to anon by default — this is not optional cleanup, it's the actual access control.**
- **Both Edge Functions are deployed and runtime-verified against real Mux** (Mux "AdGag Development" environment; `MUX_TOKEN_ID`/`MUX_TOKEN_SECRET`/`MUX_WEBHOOK_SIGNING_SECRET` are already set as Supabase secrets — don't need to re-request unless rotated):
  - `create-upload-session`: called for real, got back a genuine Mux Direct Upload URL, correctly marked the Ad `uploading`.
  - `mux-webhook`: a hand-signed (real secret, Mux's exact HMAC scheme) `video.asset.ready` payload was processed correctly end to end — Ad transitioned to `ready` with correct `playback_id`/`thumbnail_url`/`duration_ms`. Idempotency, invalid signature, missing signature, and replayed old timestamp were all verified to reject correctly. A second, unplanned event with a UUID this session never generated also showed up in the idempotency log — very likely a real Mux-originated webhook call that was correctly verified and handled.
  - **What this does NOT cover**: no actual video file has ever been PUT to a Mux upload URL and transcoded — the **hook → Supabase status ready → playback in AdGag feed** chain has only been proven with a synthetic signed payload standing in for the "Mux transcoded a real video" step, not a real video round trip. No `ffmpeg` and very little disk space in this dev environment to generate/hold a test file — this is the single biggest remaining gap in verifying the video pipeline.
- **Real builds now succeed**: `flutter build web` (full dart2js compile) and `flutter build apk --debug` (`build\app\outputs\flutter-apk\app-debug.apk`, ~166MB) both complete against the real Supabase config. `flutter analyze`: 0 issues. `flutter test`: 59/59.
- **App icon and branding are real**: `assets/branding/AdGagIkon.png` generates actual Android/iOS/web/Windows/macOS launcher icons via `flutter_launcher_icons`; `assets/branding/AdGag.png` (full lockup) is shown as a real image on the splash screen and onboarding's brand slide, not recreated with text/gradients.
- **The APK has now been installed and used on a real Android device**, surfacing two real bugs neither static analysis nor the emulator-less dev environment could have caught:
  1. **Creation-flow buttons rendered under the system gesture-nav bar, unreachable.** `camera_record_view.dart`, `trim_step.dart`, and `caption_publish_step.dart` placed their bottom-pinned controls (record button; "Use this clip"; "Publish") with no `SafeArea`/bottom-inset handling. On a device with gesture navigation the buttons sat behind/under the system nav area — visible in some cases but not tappable. Fixed: `trim_step.dart`/`caption_publish_step.dart` now wrap `body` in `SafeArea`; `camera_record_view.dart`'s `Positioned` bottom offset now adds `MediaQuery.paddingOf(context).bottom`. **Lesson: any full-bleed or bottom-pinned control in this app must explicitly account for the bottom safe-area inset — `Scaffold` does not do this automatically for `body`.**
  2. **`PGRST201` "Could not embed because more than one relationship was found for 'ads' and 'profiles'"**, live on the home feed. Once `sold_reactions` (with FKs to both `ads` and `profiles`) existed, PostgREST could no longer disambiguate the plain `ads → profiles` embed used in 4 places (`feed_repository_impl.dart`'s `getById`, `subject_repository_impl.dart`, `market_repository_impl.dart`, `profile_repository_impl.dart`) between the direct `ads_user_id_fkey` path and the indirect many-to-many path through `sold_reactions`. Fixed by disambiguating all four to `profiles!ads_user_id_fkey(username)`; verified live via `curl` (300/PGRST201 before, 200 after). **Lesson: any future junction/reaction table that FKs to both `ads` and `profiles` (e.g. a future `ad_battles`/`battle_votes`) will re-trigger this same ambiguity for existing plain `profiles(...)` embeds on `ads` — grep for `.select(".*profiles(` before adding one, and use explicit `!fk_name` embeds everywhere on `ads` going forward, not just where it broke.**
- **A third real bug, self-inflicted this time, immediately followed the two fixes above**: after fixing and rebuilding, the very next `flutter build apk --debug` was run **without** `--dart-define-from-file=env/dev.json`. `EnvConfig.assertConfigured()` (`lib/core/config/env_config.dart`) correctly throws a `StateError` when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty — but it throws in `main()` *before* `runApp()`, so Flutter never paints a first frame, and the user just sees Android's default white window background forever ("beyaz sayfada açılıyor, orada kalıyor" — opens to a white page, stays there). Confirmed via APK size: the config-less build was ~202MB vs. the correct ~166MB, and rebuilding with the flag reproduced the exact known-good size (174,225,502 bytes) exactly. **Lesson: `flutter build apk --debug` (or any `flutter build`/`flutter run`) for this project is never valid without `--dart-define-from-file=env/dev.json` — omitting it doesn't fail the build, it produces an APK that installs fine and then white-screens on every launch. Always include the flag, and if an APK's file size doesn't roughly match the last known-good size, suspect a missing dart-define before anything else.**

## Known TODOs, risks, and temporary decisions the next session must know about

- **No real video has ever flowed through the pipeline** (record → upload → Mux transcode → real webhook → ready → playback). See above — this is the top verification priority once `ffmpeg`/disk space allow it.
- **The APK has been installed and launched on a real Android device** (see the two bugs found/fixed above). Camera recording, permission prompts, and video_player playback have now executed on real hardware and work; the two layout/query bugs above are fixed but not yet re-verified on-device (next session/user retest should confirm before closing this out). No actual video has yet been published all the way through the real Mux pipeline from a real device recording — that gap (see below) is still open.
- **iOS is completely unverified** — no Mac/Xcode in this environment. The `ios/` folder exists (`flutter create .`) but has never been built.
- **No widget tests exist**, only pure-Dart logic tests. A screen can pass every current check and still throw at first real render.
- **Block filtering is incomplete by design, not oversight**: `is_blocked_either_way()` is only applied to the main feed (`get_feed_page`) and REVIEWS visibility — not subject pages, Market's Fresh Ads, profile Ads grids, or search. Documented in `0012_reports_and_blocks.sql`'s own comments.
- **Apple/Google OAuth are not configured.** `auth_repository_impl.dart`'s `signInWithApple`/`signInWithGoogle` use Supabase's hosted OAuth web flow as an MVP stand-in — before App Store submission this needs to become native `sign_in_with_apple` + `signInWithIdToken` (Apple's actual requirement when other social logins are offered).
- **Push notification dispatch is not implemented.** `notifications`/`device_tokens` tables and the in-app ACTIVITY list work today; there is no Edge Function that actually sends an FCM/APNs push. Needs a Firebase project + APNs key (see README "External Services").
- **Deep links, two kinds, one done**: the auth-callback custom scheme (`adgag://login-callback`) IS wired now — native manifest edits on both platforms + Supabase Site URL/redirect allow-list configured — and confirmed working live (email confirmation redirect). **But** Universal/App Links for sharing (`/ad/:id`, `/u/:username`, `/subjects/:id`) are still not platform-wired: the `apple-app-site-association`/`assetlinks.json` files that make those work aren't hosted anywhere yet — needs a real Apple Team ID and Android signing cert fingerprint. See README.md > Deep Links for the full distinction and the "must be reapplied if platform folders are regenerated" caveat on the native manifest edits.
- **This dev machine's disk is chronically tight.** Free space hit 0.00GB during Android build attempts. The approved-safe cleanup (Gradle caches/wrapper/daemon, npm-cache, Pub cache, Deno cache — nothing touching source/personal files/Android SDK) recovers ~11GB if builds start failing on space again; see README's disk-usage inspection and verification log for the full breakdown, including what's deliberately excluded (Android SDK system-images/AVDs, ~29.7GB, per explicit instruction not to touch SDK components).
- **Test-data pattern for any further live Supabase/Mux testing**: create a throwaway auth user via the signup endpoint, confirm its email via the Admin API (service-role key, used transiently, never stored in a file), exercise whatever needs testing, then delete the user (cascades to profile) and any orphaned rows (e.g. `ad_subjects` aren't user-owned and cascade-deleted, so subjects made during testing need manual cleanup). Always verify empty afterward with direct table counts.
- **Package version pins have burned us before** (`easy_video_editor` was pinned to a version that never existed; `intl` was incompatible with the installed Flutter SDK). Both fixed, but a reminder: verify any *new* package pin against pub.dev's actual API before committing to it, not from memory.

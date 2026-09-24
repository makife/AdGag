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
- **A third real bug, self-inflicted this time, immediately followed the two fixes above**: after fixing and rebuilding, the very next `flutter build apk --debug` was run **without** `--dart-define-from-file=env/dev.json`. `EnvConfig.assertConfigured()` (`lib/core/config/env_config.dart`) correctly throws a `StateError` when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty — but it throws in `main()` *before* `runApp()`, so Flutter never paints a first frame, and the user just sees Android's default white window background forever ("beyaz sayfada açılıyor, orada kalıyor" — opens to a white page, stays there). Fixed by rebuilding with the flag. **Lesson: `flutter build apk --debug` (or any `flutter build`/`flutter run`) for this project is never valid without `--dart-define-from-file=env/dev.json` — omitting it doesn't fail the build, it produces an APK that installs fine and then white-screens on every launch. Always include the flag.**
  - **Follow-up correction on how to verify this**: an initial check assumed APK file size was a reliable signal (config-less build ~202MB vs. a ~166MB build with config) — that turned out to be **wrong**, caught the next session when a build correctly using the flag also came out at ~202MB (size varies for unrelated reasons — ordinary code changes between builds — not a handful of short `--dart-define` strings). The actually reliable check: a debug APK isn't AOT-compiled, so the Dart kernel ships as a plain asset at `assets/flutter_assets/kernel_blob.bin` inside the APK zip — `unzip -p app-debug.apk assets/flutter_assets/kernel_blob.bin | grep -c "<the real supabase project ref>"` returns a real match count iff the dart-defines were actually compiled in, 0 otherwise. **Use this whenever there's doubt about whether a debug build has real config — never infer it from file size.**

## Live preview of speed zones and background music (2026-09-24)

Directly closes the one item round 7 explicitly deferred: "yaptıklarını yap" (do the ones you deferred) — pointing at that round's own checkpoint entry, which named live preview of music/slow-motion as the one thing not attempted.

- **Speed zones**: `TrimStep`'s main `VideoPlayerController` now carries a position listener (`_syncLivePreview`) that calls `setPlaybackSpeed(zone.factor)` whenever playback position (converted to trim-window-relative seconds, the same convention `SpeedZone`/`_Timeline` already use) falls inside a zone, and back to `1.0` outside all zones — only calling the platform method when the active zone actually *changes*, not on every position tick. **Known, accepted approximation**: `setPlaybackSpeed` pitch-shifts the preview's audio the way most players do; the real export's FFmpeg `atempo` keeps pitch correct. This is the same category of gap as the existing `ColorFilter.matrix` approximation of the export's `eq`/`hue` filter — previewed and rendered don't have to be bit-identical, just close enough to edit by.
- **Music**: a second `VideoPlayerController` (`_musicController`) plays the picked audio file, driven by the same position listener (play/pause/seek to track whichever window of the main clip — using `BackgroundAudio.startSec`/`duration` from last round — is currently showing). Deliberately reused `video_player` instead of adding a dedicated audio-player package: it already plays audio-only files via its native ExoPlayer/AVPlayer backing, and this session has hit real Kotlin/AGP build conflicts from *every* new native dependency added (`file_picker`, `share_plus`, `ffmpeg_kit_flutter_new_video`) — not a risk worth taking for a preview-only feature. All `_bgAudio` writes now route through one `_setBgAudio()` method (previously the music dialog, and the timeline's resize/remove callbacks, all wrote `_bgAudio` directly via their own `setState`) so the preview controller's create/re-sync/teardown lifecycle can't drift out of sync with whatever's actually selected. If a picked audio file's format fails to initialize in `video_player` (FFmpeg's format support at export time is broader), the preview is skipped with a snackbar rather than either crashing or silently doing nothing — export is unaffected either way, since it never goes through `video_player`.

`flutter analyze`: 0 issues. `flutter test`: 60/60. Real build verified (kernel_blob check). **Not yet confirmed on a real device** — specifically whether the pitch-shifted slow-mo preview audio is tolerable (vs. distracting) and whether a real picked music file actually initializes via `video_player` rather than hitting the fallback-to-snackbar path.

## Real-device round 7: timeline redesign, flow-reset bugs, sticker/text-animation presets (2026-09-24)

A long, ~15-item Turkish feedback message arrived after round 6's font-crash fix, closing with an explicit ultimatum: "Profesyonel bir editör yapmazsak boşa kürek çekiyoruz biz" (if we don't make a professional editor, we're wasting our effort). All items addressed except the two flagged as deferred below; **none of this has been re-tested on a real device yet** — the previous round's font-crash fix was the first time a "fixed" claim in this log turned out to be right, and every item below needs the same real confirmation before being trusted the same way.

**Timeline (`trim_step.dart`'s `_Timeline`), the two structural complaints**: "timelinde boşlukta gözüküyor çünkü timelineın tam olarak nasıl bir alan olduğu bilinmiyor" (chips look like they're floating in empty space because it's not visible what area the timeline actually is) and "timeline üzerinde kısaltılıp uzatılabilmeli" (speed/music segments should be shortenable/lengthenable directly on the timeline). Both fixed together: the timeline is now a bordered/tinted `Container` with a fixed label column (Clip / Speed / Music / Text) and a per-lane background drawn even when that lane is empty, so there's a visible track for every lane, not just for whatever happens to be placed in it. Speed zones and — new — background music both get left/right edge-drag handles (a small `_edgeHandle` grip widget) in addition to the existing tap-to-remove on the body. Music previously had **no visual representation on the timeline at all** and always covered the whole clip; `BackgroundAudio` gained `startSec`/`duration` fields (trim-window-relative, same convention as `SpeedZone`), and `VideoFilterGraphBuilder` now `atrim`s the music to that window and `adelay`s it into position (`amix=duration=first` already clamped the mix to the main track's length, so no extra padding logic was needed). Deliberately not implemented: resize collision-avoidance against sibling zones — dragging one zone's edge past another is left uncorrected, same minimal-scope call as the existing "adding a new zone checks overlap, nothing else does."

**Add-text button + presets**: confirmed already fixed going into this round (a `TextEditingController` listener was missing, so the Add button only re-evaluated its enabled state when something else, like the range slider, happened to trigger a rebuild) — 6 preset text styles (Bold/Classic/Big/Yellow/Pink/Small) with a live preview box, done in the immediately-prior turn.

**Stickers**: "stickire tıkladığımda telefonun galerisini açıyor" (tapping sticker opens the phone's gallery) — correct complaint, there was no actual sticker library. Fixed with a real picker: 10 preset symbol "stickers" (★ ♥ ✓ ✗ ➤ ‼ ● ▲ ✦ ☆) rendered as `TextOverlay`s through the *same* drawtext/bundled-font pipeline round 6 just fixed and verified working — deliberately not a new image-compositing path, since that would need its own separate verification cycle. "Choose an image from gallery" is now an explicit secondary button in the same dialog, not the only outcome of tapping Sticker. **Risk flagged honestly**: these symbols are assumed to be in Roboto's own glyph coverage (plausible — Roboto is Android's system font and has broad symbol coverage — but not confirmed against the actual bundled `Roboto-Regular.ttf`); a missing glyph in drawtext is a soft failure (renders blank, doesn't crash the export the way a missing *font family* did), so worst case a symbol doesn't render, not that music/slow-motion breaks again.

**Text animations**: added `TextAnimation` (none/slideIn/popIn) on `TextOverlay`, implemented as FFmpeg `drawtext` `x=`/`fontsize=` timed expressions (`if(lt(t,animEnd), <ramp>, <final>)`, with internal commas backslash-escaped per FFmpeg's own documented idiom for a quoted timed expression — commas are otherwise a filtergraph-level separator even inside a quoted option value). Slide-in animates `x` from off-screen-right to the target position; pop-in animates `fontsize` from 40% up to full size. **Higher-risk than the sticker addition** — `fontsize` accepting a runtime expression (vs. `x`/`y`, which definitely do) is going from documentation recollection, not a live-tested confirmation; if a future export with a pop-in text overlay fails, check this first, the same way drawtext's `fontfile=` requirement was the actual root cause behind three "unrelated" bug reports in earlier rounds.

**Create-flow reset/leave-dialog bugs** — two real, related bugs, not one:
1. "retake yapılsa bile başka her ad ekranında ... diyalog penceresi çıkıyor" (even after Retake, the leave-confirmation dialog pops up on every other create-flow screen too). Root cause found by reading `app_shell.dart`: `_onTabTap`'s guard was keyed on `navigationShell.currentIndex == _createTabIndex` — i.e. "somewhere in the AD tab" — not on whether `TrimStep` (the only screen that ever sets `hasUnsavedCreateEditsProvider`) was actually the current internal step. `CreateAdScreen` switches between subject/capture/trim/caption/publishing screens *inside* the one AD tab, so the guard fired on all of them, not just the edit screen. Fixed by also requiring `createAdFlowControllerProvider.step == CreateAdStep.trim`. Also hardened defensively: `_retake()` now clears `hasUnsavedCreateEditsProvider` explicitly instead of relying solely on `TrimStep.dispose()`'s timing.
2. "düzenleme ekranı sıfırlanmalı tekrar ad butonuna basıldığında 'what are you selling today' ekranına gelmeli" (leaving the edit screen should reset the flow; pressing AD again should land back on subject selection). `CreateAdFlowController.reset()` already existed but was never called from the leave path — `AppShell._onTabTap` now calls it whenever the AD tab is actually left (confirmed-leave or no-edits-to-confirm), so a half-finished Ad is never resumed on the next AD tap.

**Publish doesn't reach Home/Market until app restart**: `CreateAdFlowController.publish()`'s success path (once polling reaches `AdStatus.ready`) now calls `ref.invalidate()` on `feedControllerProvider`, `freshAdsProvider`, and `trendingSubjectsProvider` — same pattern `MoreMenuButton`'s delete flow already used for `feedControllerProvider`/`adsByUserProvider`. No provider previously did this for the *creation* path, only for delete.

**Feed overlay legibility/spacing, three related complaints**:
- "çok yukarıda kalıyor menü bara yakın bir şekilde konumlandır" (sits too high, position it close to the nav bar) — this was the *previous* round's own over-correction (round 6 hadn't shipped a nav-bar-overlap fix by round 7, but a fix from an earlier session had already added a large `AppSpacing.xxxl` gap on top of the actual bar-clearance math). Reduced to `AppSpacing.sm`.
- "hepsi beyaz renkte kıç kıça duruyor" (subject and nickname are both white text pressed right up against each other, easy to mis-tap one for the other) — `SubjectBadge` is now an actual chip (dark pill background + a small brand-gradient accent dot), matching what its own name always claimed it was; `CreatorHeader`'s `@username` is now dimmer/smaller/unstyled by comparison (`white70`, `w500`, 13px vs. the badge's bold white `titleMedium`) so the two are visually distinct at a glance, not just spaced further apart.
- Action-rail icons wanted circular backgrounds — added a new shared `ActionRailIcon` (`shared/widgets/action_rail_icon.dart`, a 40x40 `black38` circle) and switched all 5 action-rail buttons (`SoldButton`/`ReviewButton`/`AdThisButton`/`ShareButton`/`MoreMenuButton`) to render their icon through it instead of a bare `Icon`.

**Deliberately deferred, not attempted this round** (flagged honestly rather than half-built):
- **Live preview of music/slow-motion while editing.** Text overlays already preview live (the draggable `_OverlayPreview` widget); music and speed zones do not — music would need a synced second audio player mixed against the muted/unmuted main preview, and speed zones would need `video_player`'s `setPlaybackSpeed` remapped live only for the zone's own time window (not the whole clip) and then reset outside it. Real, scoped engineering work, not a quick addition — needs its own pass rather than being squeezed into this already-large round.
- Sticker rotation/pinch-resize reuses the existing `_onOverlayScaleUpdate` gesture handler (already supports `TextOverlay`), so no new gesture code was needed there.

`flutter analyze`: 0 issues. `flutter test`: 60/60. Real build verified: `flutter build apk --debug --dart-define-from-file=env/dev.json` succeeded, and the built APK's `assets/flutter_assets/kernel_blob.bin` was confirmed (via the `unzip -p | grep -c <project ref>` method — never file size) to contain the real Supabase project ref. **None of the specific behaviors above (drag-resize, sticker picker, text animations, the reset/leave-dialog fix, instant feed refresh) have been exercised on a real device yet** — that's the next session's first job before adding anything further on top of this round.

## Real-device round 2: navigation/playback bugs, then a deliberate editor scope expansion (2026-09-23)

Further real-device testing surfaced five more concrete bugs, all fixed:
1. **Market/Search subject and user taps used `context.goTo`** (replaces the whole route stack, including the bottom-nav shell) **instead of `context.pushTo`** — left no back destination, forcing users out of the app. Fixed in `market_screen.dart`/`search_screen.dart` (3 call sites). `subject_badge.dart` already used `pushTo` correctly — worth grepping for `context.goTo` before adding any new subject/profile navigation, since `goTo` is very rarely the right choice for a "drill into detail" tap.
2. **`StatefulShellRoute.indexedStack` keeps every bottom-nav tab mounted, not paused, when hidden** — the feed's video kept playing behind the AD (creation) tab, and didn't resume on returning to Home. Fixed by tracking the active branch in `activeShellBranchIndexProvider` (`app_shell.dart`) and having `FeedScreen` pause/resume its pool on change. **Lesson: `IndexedStack`-based navigation (this app, or any Flutter app using `StatefulShellRoute.indexedStack`) never pauses hidden branches on its own — any screen with playing media needs to watch tab-visibility explicitly, app-lifecycle observers alone aren't enough.**
3. **No tap-to-pause or mute control existed on the feed player.** Added in `ad_video_card.dart`: tap toggles play/pause (center play icon when paused), a persistent mute button (`isFeedMutedProvider`, shared across cards so it survives swiping).

Then real-device testing of the creation flow surfaced a much bigger gap: the trim screen only showed a static frame (never called `.play()`), had no retake/delete option, and — the substantive complaint — offered no editing tools beyond trim. You explicitly requested a comprehensive editor with real effects ("font desteği gif desteği bir çok şey olsun" / font support, GIF support, lots of things), overriding CLAUDE.md section 4's "don't build a CapCut clone" default for this project.

**What shipped**: investigated `easy_video_editor` (already a dependency, chosen for trim) and found it already supports, natively, with no new dependency: `speed` (slow motion / fast forward — directly answers your "can't even slow-mo part of the video" example), `rotate`, `flip`, `removeAudio`, `crop`, `compress` — it just wasn't exposed in the UI. Expanded the trim-only `VideoTrimmer` interface into `VideoEditorService` (`core/media/video_editor_service.dart` + `easy_video_editor_service.dart`, chains every requested operation into one native export instead of N intermediate files) and rebuilt `trim_step.dart` into a real edit screen: playing/looping preview with live rotate/flip/speed/mute feedback, trim, speed slider (0.5x–2x), rotate, flip, mute, and a Retake button. `CreateAdFlowController.onVideoCaptured` now always routes through this step (previously skipped entirely for clips already ≤10s, which meant a short clip could never reach any editing tool at all). Added a matching Retake action to the caption/publish step too. A "nothing changed" fast path skips re-encoding entirely when the user picks no edits, so the common case still doesn't cost a native export.

**What did NOT ship, deliberately, and why**: burning text or GIF stickers into the exported video. `easy_video_editor` has no compositing/overlay API at all — that needs either a GPL-licensed toolchain (ffmpeg's `drawtext`/`overlay` filters, a real App Store/Play Store distribution licensing question) or a custom native frame-compositing pipeline — a materially larger, separate piece of work with its own licensing decision to make first, not something to silently bolt on. Flagged back to you rather than either skipped silently or built blind; see README.md's editor section for the same detail. Crop/compress were deliberately left unexposed in the UI: crop's aspect-ratio presets don't fit a 9:16-only vertical format (section 4), and compress is an internal quality/size concern, not a user-facing "effect."

Also, separately, you asked for the profile page to show own Ads, allow deleting them, and allow account edits — none of which existed (`ProfileScreen` was a Phase A placeholder: name + sign-out only):
- **Delete own Ad**: added to `MoreMenuButton`'s "..." menu (confirmation dialog, `DraftAdRepository.deleteAd` already existed server-side — this was purely a missing UI wire-up).
- **Profile page rebuilt**: own-Ads grid (reusing the same pattern as `PublicProfileScreen`, tap-through gets the same delete option above), Ads/SOLD/Views stats (summed client-side from the fetched page — see the code comment on the accuracy limit past 30 Ads), a Settings entry.
- **New `EditProfileScreen`** (`/profile/edit`): display name + bio, backed by a new `ProfileRepository.updateProfile()` — RLS/column grants for this already existed (`profiles_update_own` + column-level grants in `0002_profiles_and_auth_trigger.sql`, restricting it to `display_name`/`avatar_url`/`bio`), this was also purely a missing client-side wire-up, no migration needed.
- **Not built**: avatar image upload. No Supabase Storage bucket, RLS policy, or upload flow exists anywhere in this codebase yet — a real follow-up task, not a quick addition.

`flutter analyze`: 0 issues. `flutter test`: 61/61 (2 new: retake, and "every captured clip routes to edit, not just long ones" replacing the old skip-when-short-enough test).

## Real-device round 6: the actual FFmpeg crash found and fixed (2026-09-24)

The log-truncation fix from round 5 paid off immediately — a fresh screenshot showed the real error this time: `[Parsed_drawtext_5] Cannot find a valid font for the family Sans` / `Error initializing filters`. **This is the one root cause behind every "music doesn't play"/"slow-motion doesn't show" report across the last several rounds**: FFmpeg's `drawtext` filter has no fontconfig-discoverable "Sans" family to fall back to on Android (unlike desktop Linux, where a bare `font=` name usually resolves against installed system fonts) — so any export that included a text overlay failed outright at the filter-graph-initialization stage, and because export is one single FFmpeg pass, that failure took down music/slow-motion/everything else in the *same* export too, even though those specific filters were themselves fine. Every prior round's "music/slow-motion doesn't work" symptom was very likely this, not three separate effect bugs — text overlays were involved in the failing test cases each time.

**Fix**: `assets/fonts/Roboto-Regular.ttf` (Apache-2.0, downloaded from Google Fonts, verified as genuine TrueType data via the `file` command before committing — not assumed) is now bundled, extracted once per app session to a real filesystem path via `rootBundle.load` + `getTemporaryDirectory` (drawtext's `fontfile=` parameter needs an actual path on disk, not an asset-bundle reference — Flutter assets are packed into the APK and aren't directly file-accessible), and passed through as a required `VideoFilterGraphBuilder.build()` parameter instead of relying on family-name lookup. **This should be the fix, not a hedge** — but hasn't yet been confirmed against a real device export at time of writing; the next test report is the actual confirmation.

Also fixed, per pointed feedback that the timeline was borderline unusable:
- **Trim-window drag handle's touch target was 16px, same as its visual size** — well below any reasonable minimum, genuinely hard to grab reliably. Now a 44px-tall hit area with the same 16px visual pill centered inside it (visual size unchanged, only the touch target grew).
- **Speed-zone/overlay markers on the timeline deleted on a bare tap, instantly, no confirmation** — trivially easy to trigger by accident while just trying to look at or interact with them. Now shows a confirm dialog first.
- **Overlay markers were an unlabeled 16px icon** ("pire kadar ikon" — flea-sized icon, no way to tell what it represents). Now a labeled chip showing the actual overlay text (or "sticker" for images), matching the speed-zone chip's visual weight and size.
- **Switching bottom-nav tabs away from the edit screen with in-progress edits now asks for confirmation** (`hasUnsavedCreateEditsProvider`, a `StateProvider<bool>` `TrimStep` keeps in sync with its own edit state, read by `AppShell` before `goBranch` when leaving tab index 2 specifically) — previously it switched silently (the audio-continuing-to-play half of this was fixed in round 5; the missing warning dialog itself is what's fixed here).

`flutter analyze`: 0 issues. `flutter test`: 60/60. Real build verified (config + font bundling both confirmed present in the built APK via direct inspection, not assumed).

## App icon replaced; Market screen redesigned (2026-09-23)

Two independent changes, both shipped and verified together in one build:

- **New app icon**: `assets/branding/AdGagIkon.png` replaced with a new source image (a gradient "fast-forward" mark); all launcher icons regenerated via `dart run flutter_launcher_icons` (Android/iOS/web/Windows/macOS). Worth knowing for next time this file gets replaced: it arrived saved as JPEG bytes despite the `.png` extension (some export/save path on the user's end does this — not something to treat as corruption and revert, as an earlier round in this same session mistakenly did with a different, unintended file change) — `flutter_launcher_icons`' underlying image library detects format from content, not extension, so this worked fine without renaming anything.
- **MarketScreen redesigned**, per explicit direction: Fresh Ads now leads as a horizontal scroll (previously Trending Subjects' position at the top); Trending Subjects moved below as a vertical list with larger type. Tapping a subject expands an `AnimatedSize` + `AnimatedRotation`-chevron horizontal preview of that subject's own Ads directly beneath it — accordion behavior (one `_expandedSubjectId` field: opening one closes whichever was open; tapping the open one again closes it). Reuses `subjectAdsProvider` (already existed for the Subject page's own tabs) rather than adding a new provider.
  - **Real bug hit and fixed while building this**: converting `MarketScreen` from `ConsumerWidget` to `ConsumerStatefulWidget` (needed for the `_expandedSubjectId` local UI state), the new `_MarketScreenState.build` was written as `build(BuildContext context, WidgetRef ref)` — the `ConsumerWidget` signature, not `ConsumerState`'s. `ConsumerState.build` takes only `BuildContext`; `ref` is an inherited instance field already in scope, not a build parameter. The analyzer error for this ("isn't a valid override of State.build") doesn't obviously say "wrong Riverpod widget type" at a glance — worth remembering as a checklist item any time a Consumer*Widget* is converted to a Consumer*StatefulWidget*+State.

## Real-device round 5: FFmpeg error display, gestures, tab-switch audio, naming (2026-09-24)

Real-device testing of "take four" (below) surfaced a real, screenshot-confirmed bug plus several UX complaints, all fixed:

- **The FFmpeg failure message shown to the user was useless** — `getAllLogsAsString()` returns the *entire* session log, which starts with a long build-configuration banner (compiler flags, enabled libraries, paths) before anything about the actual run; dumping it raw into the error string (what `FfmpegVideoExportService` did before this round) meant a failed export's error message was just the banner, never the real reason — confirmed via a user screenshot showing exactly that. Fixed: now shows only the last ~12 non-empty log lines, which is where FFmpeg actually reports why a run failed. **This means every "music doesn't play"/"slow-motion doesn't show" report before this fix was very likely the FFmpeg pipeline failing outright on every advanced edit — not the effects silently not applying — and the real reason was never visible to diagnose. Next failure report should include the actual error text now, not the banner.**
- **Found and fixed one real, concrete bug** while investigating: `_escapeDrawtext`'s single-quote escaping had an extra backslash (`r"'\\\''"` — 6 characters — instead of the correct 4-character shell-style escape `r"'\''"`), which would corrupt the filter graph for any text overlay containing an apostrophe. Whether this was *the* cause of the reported failures is unconfirmed (the fixed error display will show whether the next failure looks like a filtergraph parse error or something else, e.g. `h264_mediacodec` not actually being a valid encoder name in this specific FFmpeg build — flagged as a real possibility during investigation but not yet confirmed or ruled out).
- **Overlay gestures were genuinely bad, per direct feedback**: dragging only, no pinch-to-resize, no rotate, and long-press instantly deleted (easily triggered by mistake while trying to drag). Replaced with `onScaleStart`/`onScaleUpdate` (one `GestureDetector` callback pair handles one-finger drag *and* two-finger pinch/rotate together — mixing `onPanUpdate` with `onScaleUpdate` on the same detector isn't valid, they fight over the gesture arena) and a small always-visible × button instead of long-press. `ImageOverlay` gained `rotationDegrees`, applied via FFmpeg's `rotate` filter (`c=none` to keep transparent corners) before compositing. **Text overlays cannot rotate** — FFmpeg's `drawtext` filter has no rotate parameter; doing it anyway would mean rendering text to an image first, a materially bigger feature, not a quick addition. Pinch-to-resize works for both text (`fontSize`) and images (`widthPercent`).
- **TrimStep's preview kept playing (audibly) when switching to a different bottom-nav tab mid-edit** — the same `IndexedStack`-doesn't-pause-hidden-branches issue fixed for the feed screen earlier in this project's history, just never wired up here since this screen didn't exist yet at that time. Now listens to `activeShellBranchIndexProvider` the same way.
- **App display name was wrong on both platforms** — Android's `android:label` was `"adgag"` (lowercase, in the gitignored/regenerated `android/AndroidManifest.xml` — reapply if that folder is ever regenerated) and iOS's `CFBundleDisplayName` was `"Adgag"` (also gitignored). Both fixed to `"AdGag"`.
- **Explained, not changed**: `fetchTrendingSubjects()` (`market_repository_impl.dart`) orders by raw `ad_subjects.ads_count` descending, limit 15 — there is no time-decay/velocity signal yet, so it's genuinely "most-ever-published-to" rather than "trending" in a recency sense, and yes, any subject can appear there once it has enough Ads relative to the current top 15. This is the same MVP simplification CLAUDE.md sections 10/59 already call out as acceptable for v1 — a real trending algorithm (time-windowed activity) is a legitimate future upgrade, not something this round changed.

**Known still-open gap, restated directly per feedback**: the timeline still isn't interactive for editing zone/overlay boundaries directly (drag a zone's edges *on* the timeline to resize it) — zones/overlays are added via a dialog and only *shown* correctly positioned on the timeline, matching the scope note already in `TrimStep`'s doc comment. Not addressed this round; flagged again since the user explicitly called the timeline "dumb" for this reason.

`flutter analyze`: 0 issues. `flutter test`: 60/60. Real build verified (config confirmed via kernel_blob check).

## Comprehensive editor, take four: color filters, timeline-trim, music fixed for real (2026-09-23)

Three more concrete asks, all delivered:

1. **Color filters** (warm/cool/B&W) — `AppColorFilter` on `VideoProject`, applied via FFmpeg `eq`/`hue` (forces the FFmpeg render path, same as a speed zone — no equivalent in `easy_video_editor`), with a `ColorFilter.matrix` approximation for live preview so what's shown while editing matches what renders.
2. **Trim moved onto the timeline** — no longer a separate slider above it. The timeline now spans the *original* captured clip with a draggable highlighted window (drag to move where the selected up-to-10s slice starts), speed zones and overlay markers positioned inside it by real time fraction.
3. **Background music, actually fixed this time** — the "take two" conclusion that `file_picker` breaks this project's Android build was **wrong in its explanation**, caught by actually reading the package source instead of accepting the first plausible-looking cause: it wasn't file_picker's *scope*, it was 11.0.3 specifically (pinned back then to dodge a win32 conflict) unconditionally applying its own outdated embedded Kotlin Gradle Plugin (1.8.22), older than this project's. Confirmed by reading `android_file_picker`'s actual `build.gradle.kts` (the federated rewrite's Android implementation): it explicitly checks AGP version and properly defers to AGP 9's built-in Kotlin instead of forcing its own. **Lesson: when a plugin's Android build fails with "cannot find symbol" for a class that's clearly present in its own source, suspect a Kotlin/AGP toolchain version conflict specific to *that plugin's own build.gradle*, not the plugin's feature scope — check the plugin's actual `android/build.gradle(.kts)` for a hardcoded old Kotlin version before concluding the package itself is unusable.**
   - Using current `file_picker` (^13.1.0) reintroduced the win32-version conflict with `share_plus` that 11.0.3 had been dodging — fixed by bumping `share_plus` to ^13.3.0 too (verified first: this app already uses the modern `SharePlus.instance`/`ShareParams` API, not the older static one, so no call-site changes needed).
   - That then surfaced one more, genuinely confusing error: `share_plus-13.3.0`'s own `SharePlusPendingIntent` class "unresolved reference" despite the `.kt` file demonstrably existing in the package source. This was a **stale Gradle module cache** from the multiple share_plus versions resolved across this session's back-and-forth (12.0.2 → attempted 13.3.0 → back to 12.0.2 → 13.3.0 again) — `flutter clean` (which doesn't touch the Gradle *dependency* cache, just this project's own build outputs) resolved it, the same fix pattern as two earlier stale-cache incidents this session. **Lesson: an "unresolved reference" to a class that's clearly present in the dependency's own source is a stale-incremental-build symptom worth ruling out with `flutter clean` before assuming the dependency itself is broken.**

`flutter analyze`: 0 issues. `flutter test`: 60/60. Real build verified (config confirmed via kernel_blob check) after each of the three fixes above.

## Comprehensive editor, take three: merged into one screen, quality fixed (2026-09-23)

Direct, blunt feedback on the round above: a separate "Advanced editor" screen and a distinct "Export" concept (its own button, its own step, after the actual editing felt done) were both unwanted and confusing — "bu videosu düzenlenir sonra niye eksport edilir" (it gets edited, then why does it get *exported*?). Correct: from a user's perspective there's one editing screen and one "Continue," matching how the rest of the creation flow already works (capture → edit → caption, each with one forward action, never a named intermediate processing step).

**Fixed**: deleted `video_editor_screen.dart`; folded rotate/flip/mute/slow-motion-zones/text/sticker into `TrimStep` as one screen — a horizontal-scrolling tool row (not a second screen behind an "Advanced" button) and a real proportional timeline underneath it (colored speed-zone segments and overlay markers positioned by actual start/end fraction of the clip, tap to remove — not the removable-chip list from the deleted screen). `VideoProject` gained `rotation`/`flip`/`removeAudio` fields so the FFmpeg pipeline can carry simple whole-clip transforms through the *same* render pass as zones/overlays, instead of needing a separate pass. The button says "Continue" and, while working, "Processing… N%" — matching the publish step's own "Uploading… N%" wording, not a distinctly-named "Export." Which render path runs (the fast `easy_video_editor` one, or the heavier FFmpeg one) is now decided automatically by whether any zone/overlay was added — invisible to the user, exactly the "you edit, then you continue" model asked for.

**Also fixed**: FFmpeg-path output was visibly low quality — hardware encoders (`h264_mediacodec`/`h264_videotoolbox`) don't pick a sane default bitrate on their own; without an explicit rate the encoder falls back to something quite low regardless of source resolution. Added `-b:v 10M`. Also stopped building an audio filter chain at all when the mute toggle is on (previously built it, then just didn't map it — wasted FFmpeg work, not a correctness bug, but pointless).

## Comprehensive editor, take two: FFmpeg engine actually shipped (2026-09-23)

The filter/overlay research from round 3 (below) said no non-GPL, actively-maintained package could do this — that stood until the user pushed back with a specific, correct technical counter-argument: an LGPL FFmpeg build using **hardware** H.264 encoders (`h264_mediacodec`/`h264_videotoolbox`, OS system libraries, GPL-irrelevant) instead of the GPL-only software `libx264` avoids GPL entirely. That's correct, and changed the outcome — this is now built, not just researched.

**Dependency verification, done properly before writing any code**: the user's literal suggestion (`ffmpeg_kit_flutter_min: ^6.0.3`) is dead — pub.dev confirms `isDiscontinued: true`, and it's the original `arthenica/ffmpeg-kit` whose Maven Central binaries were pulled 2025-04-01. Found and verified the real option instead: `ffmpeg_kit_flutter_new_video` (`sk3llo/ffmpeg_kit_flutter` fork, publisher antonkarpenko.com) — confirmed live via pub.dev's API before pinning: `license:lgpl-3.0` tag (not a `-gpl` variant), published 2026-07 (current), Dart-3-compatible, 130/160 pub points. Deliberately the **`_video`** tier, not `_min` as literally requested: `_min`'s external-library table (scraped from the pub.dev page) excludes `freetype`/`fontconfig`, which `drawtext` needs to render text at all — `_video` adds exactly those while still excluding all GPL codecs (x264/x265/xvidcore/vid.stab stay `-gpl`-only). This distinction was verified from the package's own published library table, not assumed.

**What got built** (all new, `flutter analyze` clean, 60/60 tests):
- `features/create_ad/domain/video_project.dart` — immutable `VideoProject` timeline state: `SpeedZone` (time-ranged speed multiplier), `BackgroundAudio` (volume + fade in/out), `TextOverlay`/`ImageOverlay` (positioned by percentage, timed by `startSec`/`duration`). Plain Dart, no Flutter/FFmpeg dependency — deliberately kept clean of both the UI and native layers.
- `core/media/video_filter_graph_builder.dart` — pure-Dart FFmpeg `-filter_complex` construction. Speed zones: splits video+audio into segments at every zone boundary, `setpts=(PTS-STARTPTS)/factor` per video segment, `atempo=factor` per audio segment (keeps audio pitch-correct and in sync through a slow-motion window, not just the video track alone), `concat` back together. Overlays: `drawtext`/`overlay` with `enable='between(t,start,end)'` for the timed show/hide window. Background audio: `amix`+`afade`. This file has zero FFmpeg-package imports — it only builds a `List<String>` of arguments, independently testable from execution.
- `core/media/ffmpeg_video_export_service.dart` — the actual `FFmpegKit.executeWithArgumentsAsync` call: streams 0.0-1.0 progress from FFmpeg's own `Statistics.getTime()`, picks `h264_mediacodec`/`h264_videotoolbox` by `Platform.isAndroid`/`isIOS` (mpeg4 software fallback only for the desktop platforms this app doesn't actually target), resolves/throws based on `ReturnCode`.
- `features/create_ad/presentation/screens/video_editor_screen.dart` — the actual screen: looping preview, drag-to-reposition overlays (`GestureDetector.onPanUpdate` converting pixel delta to the model's `xPercent`/`yPercent`, long-press to delete), dialogs to add a speed zone (with a live slow-motion preview via `video_player`'s own `setPlaybackSpeed` — not just the exported result) or a timed text/image overlay, removable chips for everything added, Export button with a live progress bar. Reached from `TrimStep` (the simple, fast default editor, still fully intact) via an explicit "Advanced" action — not a replacement, so the common case that needs none of this never pays for FFmpeg at all.

**What did NOT get built, deliberately**: background-music file picking. `file_picker` (needed since `image_picker` doesn't handle audio) collided with the other native plugins already applying their own Kotlin Gradle Plugin in this project — confirmed twice (including after a full `flutter clean` + fresh `pub get`) as a real, reproducible `cannot find symbol FilePickerPlugin` compile error, not a stale-cache fluke. Removed rather than spend further build cycles debugging a 5-plugin Kotlin classpath conflict right after finally getting FFmpeg stable. `VideoProject.bgAudio` and the filter-graph builder's `amix`/`afade` handling are fully implemented and ready — only the "pick a file" entry point is missing. **Lesson for whoever adds this next**: try a *different* audio-picking package first (not `file_picker`) to sidestep this specific conflict, or investigate whether pinning a shared Kotlin Gradle Plugin version project-wide (the "Future versions of Flutter will fail to build" warning that's been present all session, now with 4-5 plugins triggering it) resolves it more durably than avoiding the one plugin that happened to surface it first.

**The build itself was the other real story here** — not a code problem, a disk-constrained-dev-machine problem: the very first attempt at building with `ffmpeg_kit_flutter_new_video` added ran for 655 seconds before the Gradle daemon died ("disappeared unexpectedly"); a retry hit the same fate at disk-critical levels requiring a proactive kill + cache-clean + retry (per your standing approval to redo that cleanup automatically when needed); a *third* attempt was let run uninterrupted with full headroom and **succeeded after 2594.9 seconds (~43 minutes)** — the actual cost of a first-time multi-ABI native FFmpeg download+link on this machine, not a hang. Every subsequent build (once Gradle's dependency cache had it) completed in **~2 minutes** — this was a one-time cost, not a recurring one, as long as `~/.gradle/caches` isn't cleared again. **Lesson: don't assume a long-running build on this machine is stuck — check disk trend (oscillating, not monotonically draining, is a good sign) and process CPU (still accumulating means still working) before killing it; but a genuine sub-500MB-free trend is real and should be acted on, not waited out.**

## Real-device round 3: editor polish, front camera, real avatar upload, filter/overlay research (2026-09-23)

Continued real-device testing of the round-2 editor found real regressions/gaps in what had just shipped, all fixed:
- **Rotate preview overflowed the canvas.** `Transform.rotate` only rotates visually — it doesn't tell its parent the layout size changed, so a 90°/270° turn on a 9:16 clip overflowed the fixed preview box. Fixed by switching to `RotatedBox` (built for exactly this: quarter-turn rotation that correctly swaps the reported layout size), in `trim_step.dart`.
- **The trim slider looked broken for any clip already ≤10s** (which is every clip now, since round 2 made the edit step always show): `_maxStartSeconds` computes to 0 when there's no room to trim, so the slider had `min == max == 0` — technically correct, but indistinguishable from "unresponsive" to a user with no explanation. Fixed by showing "Already fits within 10s — nothing to trim" instead of a dead slider in that case.
- **No undo for the edit step's own selections.** Added a "Reset" action (distinct from "Retake", which discards the capture and goes back to record/import — Reset just clears speed/rotation/flip/mute/trim back to defaults on the same clip).
- **No front camera.** `camera_record_view.dart` only ever opened the back camera. Added a switch-camera button (shown only when `availableCameras()` actually returns 2+) that disposes and reopens the `CameraController` on the other `CameraLensDirection`.

**Avatar upload shipped for real** — infrastructure and all, not deferred this time, since it was explicitly requested twice and was actually well-scoped (unlike filters/overlay below): `0018_avatar_storage.sql` creates a public `avatars` Storage bucket + 4 RLS policies on `storage.objects` (public read; owner-only insert/update/delete, ownership checked from the `{user_id}/...` path prefix via `storage.foldername(name)`) — pushed to the real project and verified live (bucket row + all 4 policies confirmed via `supabase db query --linked`). `ProfileRepository.uploadAvatar(File)` uploads to `{userId}/avatar.<ext>` with `upsert: true` (so re-uploading replaces, not accumulates) and a cache-busting query param on the returned URL (same path every time would otherwise show a stale cached image after re-upload). `EditProfileScreen` gained a tappable avatar circle wired to `image_picker` (already a dependency — no new one added); `ProfileScreen`'s header was restructured to show the avatar next to the stats row instead of a stats-only left column.

**Filter (color grading) and overlay (text/sticker/animated GIF) support — researched properly this time, not just asserted**: both are still not implemented, but here's the actual current state of the ecosystem, checked live via WebSearch + pub.dev's API (not from memory):
- `ffmpeg_kit_flutter` is **officially retired** — its native binaries were pulled from Maven Central/CocoaPods/npm on 2025-04-01, no maintainer, no security patches. The community fork (`ffmpeg_kit_flutter_new`) is explicitly a **"Full GPL"** build — confirms the licensing concern flagged earlier was real, not hypothetical.
- `tapioca` (the one non-FFmpeg Flutter package found that claims native text-overlay + color-filter support via AVFoundation/Android Mp4Composer) is **abandoned**: last published 2022-09-14 (4 years ago), `environment: sdk: >=2.12.0 <3.0.0` — predates Dart 3 entirely, almost certainly won't resolve cleanly against this project's SDK. Verified via pub.dev's package API directly, the same way `easy_video_editor`'s version was verified earlier — not taken from a blog post's claim that it's "maintained."
- **No actively-maintained, non-GPL Flutter package currently does burned-in video text/filter compositing.** This isn't a permanent state of the ecosystem, but it's the real state of it right now.
- **Recommended path forward, not yet built**: implement both as an **in-app-only layer** — a color filter (warm/cool/B&W via Flutter's own `ColorFiltered` widget, zero native dependency) and text/sticker overlays, applied live wherever AdGag plays its own videos (feed, subject viewer, profile viewer), stored as Ad metadata (a new `ads` column + `create_draft_ad`/`update_draft_ad` RPC parameter — a schema change, needs the same care as any RPC signature change per the `create_draft_ad` overload lesson earlier in this file). The real tradeoff to accept: this would **not** be burned into the raw video file, so a video shared externally (Instagram/WhatsApp/TikTok via the native share sheet) would lose the filter/text — only playback inside AdGag itself would show it. That's a genuine product compromise, not a hidden one — flagged here so it's a deliberate choice, not a surprise later. A future native/licensing-accepting path remains open if burned-in export becomes a hard requirement.

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
- **Text/image overlay burned into the exported video is now implemented** (see "Comprehensive editor, take two" above) — `VideoEditorScreen`, `VideoProject`, `VideoFilterGraphBuilder`, `FfmpegVideoExportService`, using the LGPL `ffmpeg_kit_flutter_new_video` package and hardware H.264 encoding, not GPL. Animated GIF *as a moving overlay* specifically is not — `ImageOverlay` composites a single static image/frame, not an animated GIF's multiple frames; true animated-GIF overlay would need a different `overlay` filter approach (or converting the GIF to a short video first) — a smaller follow-up on top of infrastructure that already exists, not a from-scratch problem anymore.
- **Background-music file picking is now implemented** (see "Comprehensive editor, take four" below) — the `file_picker` conflict noted in "take two" was a real bug but a fixable one: 11.0.3's own outdated embedded Kotlin plugin, not the package's scope. Fixed by using current `file_picker` + bumping `share_plus` to resolve the resulting win32 version conflict.
- **The editor's timeline is a real proportional visualization now** (see "take three" above) but still not draggable/resizable — zones/overlays are added via a short dialog, then shown correctly positioned/sized on the timeline, tap to remove. Dragging a zone's edges directly on the timeline to resize it is the next visual-polish step, not built yet; `VideoProject`/the filter-graph builder don't care how a zone was created, so it's a pure UI addition when it happens.
- **Avatar image upload is not implemented.** `EditProfileScreen` only edits display name/bio. No Supabase Storage bucket, bucket RLS policy, or client upload flow exists yet for `avatar_url` — needs that infrastructure decision made first (which bucket, size/type limits, whether images get processed/resized) before it's a quick addition.
- **Profile Ads/SOLD/Views stats are computed client-side from `fetchAdsByUser`'s first page (limit 30)**, not a true account-wide total — accurate for typical MVP-stage creators, wrong once someone has published more than 30 Ads. Matches the "isolate the counter mechanism so aggregation can move to queues/event processing later" guidance in CLAUDE.md section 58 — the real fix is a maintained counter on `profiles`, not a bigger client query.

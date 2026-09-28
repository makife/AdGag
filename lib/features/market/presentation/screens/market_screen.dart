import "dart:async" show Timer, unawaited;
import "dart:math" as math;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../../core/localization/generated/app_localizations.dart";

import "../../../../core/router/app_shell.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/video/video_providers.dart";
import "../../../daily_ad/presentation/widgets/daily_ad_banner.dart";
import "../../../feed/domain/ad.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../../subjects/domain/subject_ads_sort.dart";
import "../../../subjects/presentation/providers/subject_providers.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../providers/market_providers.dart";
import "search_screen.dart";

/// MARKET / Discovery (CLAUDE.md section 12) — "the market of ideas/Ads",
/// not a commerce marketplace. Fresh Ads leads as a horizontal scroll
/// (what's new right now); Trending Subjects follows as a vertical list
/// — each subject expands in place to a horizontal preview of its own
/// Ads (accordion: opening one closes whichever was open), rather than
/// forcing a navigation away from Market just to see what a trending
/// subject actually looks like.
class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  String? _expandedSubjectId;

  void _toggleSubject(String subjectId) {
    setState(() => _expandedSubjectId =
        _expandedSubjectId == subjectId ? null : subjectId,);
  }

  @override
  Widget build(BuildContext context) {
    final trendingAsync = ref.watch(trendingSubjectsProvider);
    final freshAsync = ref.watch(freshAdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).navMarket),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SearchScreen(),),),
            ),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          const DailyAdBanner(),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(AppLocalizations.of(context).marketFreshAds,
                style: Theme.of(context).textTheme.titleMedium,),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 170,
            child: freshAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) =>
                  const SizedBox.shrink(),
              data: (List<Ad> ads) => _PreviewStrip(ads: ads, tileWidth: 96),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              AppLocalizations.of(context).marketTrendingSubjects,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          trendingAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stackTrace) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text("$error"),
            ),
            data: (List<AdSubject> subjects) => Column(
              children: <Widget>[
                for (final AdSubject subject in subjects)
                  _SubjectExpandableTile(
                    subject: subject,
                    isExpanded: _expandedSubjectId == subject.id,
                    onTap: () => _toggleSubject(subject.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _SubjectExpandableTile extends StatelessWidget {
  const _SubjectExpandableTile(
      {required this.subject, required this.isExpanded, required this.onTap,});

  final AdSubject subject;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md,),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    "${subject.displayName.toUpperCase()}™",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)
                      .subjectAdCount("${subject.adsCount}"),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,),
                ),
                const SizedBox(width: AppSpacing.xs),
                AnimatedRotation(
                  duration: AppMotion.medium,
                  turns: isExpanded ? 0.5 : 0,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? _SubjectAdsPreviewRow(subjectId: subject.id)
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SubjectAdsPreviewRow extends ConsumerWidget {
  const _SubjectAdsPreviewRow({required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ad>> adsAsync =
        ref.watch(subjectAdsProvider((subjectId, SubjectAdsSort.trending)));

    return SizedBox(
      height: 150,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: adsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) => Center(
              child: Text(AppLocalizations.of(context).genericLoadFailed),),
          data: (List<Ad> ads) {
            if (ads.isEmpty) {
              return Center(
                  child: Text(AppLocalizations.of(context).emptySubjectFeed),);
            }
            return _PreviewStrip(ads: ads, tileWidth: 84);
          },
        ),
      ),
    );
  }
}

/// A horizontal row of Ad tiles whose on-screen tiles come alive one after
/// another (owner request): every [_step] the next visible tile swaps its
/// still thumbnail for a short looping preview. Previews are Mux animated
/// WebP images, not video players — Market must not hold hardware video
/// decoders (the native editor needs them all; see FeedScreen).
class _PreviewStrip extends ConsumerStatefulWidget {
  const _PreviewStrip({required this.ads, required this.tileWidth});

  final List<Ad> ads;
  final double tileWidth;

  @override
  ConsumerState<_PreviewStrip> createState() => _PreviewStripState();
}

class _PreviewStripState extends ConsumerState<_PreviewStrip> {
  static const Duration _step = Duration(seconds: 3); // = the preview's length
  static const int _marketTab = 1;

  final ScrollController _scroll = ScrollController();
  Timer? _timer;
  int _playing = 0;
  double _viewportWidth = 0;

  double get _stride => widget.tileWidth + AppSpacing.sm;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_step, (_) => _advance());
  }

  /// Moves to the next tile, staying within the ones currently on screen.
  void _advance() {
    if (!mounted || widget.ads.isEmpty) {
      return;
    }
    final double offset = _scroll.hasClients ? _scroll.offset : 0;
    final int first = math.max(0, ((offset - AppSpacing.lg) / _stride).ceil());
    final int visible =
        math.max(1, ((_viewportWidth - AppSpacing.lg) / _stride).floor());
    final int last = math.min(widget.ads.length - 1, first + visible - 1);
    int next = _playing + 1;
    if (next < first || next > last) {
      next = first;
    }
    if (next != _playing) {
      setState(() => _playing = next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only animate while Market is the visible tab and nothing covers it.
    final bool active =
        ref.watch(activeShellBranchIndexProvider) == _marketTab &&
            TickerMode.valuesOf(context).enabled;
    final videoService = ref.watch(videoServiceProvider);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewportWidth = constraints.maxWidth;
        return ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: widget.ads.length,
          itemBuilder: (BuildContext context, int index) {
            final Ad ad = widget.ads[index];
            final String? playbackId = ad.playbackId;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _AdThumbnail(
                ad: ad,
                width: widget.tileWidth,
                animatedUrl: active && index == _playing && playbackId != null
                    ? videoService.animatedPreviewUrl(playbackId)
                    : null,
                onTap: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SubjectAdsViewerScreen(
                          ads: widget.ads, initialIndex: index,),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdThumbnail extends StatelessWidget {
  const _AdThumbnail(
      {required this.ad,
      required this.width,
      required this.onTap,
      this.animatedUrl,});

  final Ad ad;
  final double width;
  final VoidCallback onTap;

  /// When set, a looping preview plays over the still thumbnail.
  final String? animatedUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (ad.thumbnailUrl != null)
                  CachedNetworkImage(
                      imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover,)
                else
                  Container(color: Colors.black12),
                if (animatedUrl != null)
                  CachedNetworkImage(
                    imageUrl: animatedUrl!,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (BuildContext context, String url) =>
                        const SizedBox.shrink(),
                    errorWidget:
                        (BuildContext context, String url, Object error) =>
                            const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

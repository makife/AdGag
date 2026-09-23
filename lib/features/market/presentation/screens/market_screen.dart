import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
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
    setState(() => _expandedSubjectId = _expandedSubjectId == subjectId ? null : subjectId);
  }

  @override
  Widget build(BuildContext context) {
    final trendingAsync = ref.watch(trendingSubjectsProvider);
    final freshAsync = ref.watch(freshAdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Market"),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
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
            child: Text("Fresh Ads", style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 170,
            child: freshAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
              data: (List<Ad> ads) => ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: ads.length,
                itemBuilder: (BuildContext context, int index) {
                  final Ad ad = ads[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _AdThumbnail(
                      ad: ad,
                      width: 96,
                      onTap: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SubjectAdsViewerScreen(ads: ads, initialIndex: index),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text("Trending Subjects", style: Theme.of(context).textTheme.titleMedium),
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
  const _SubjectExpandableTile({required this.subject, required this.isExpanded, required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    "${subject.displayName.toUpperCase()}™",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  "${subject.adsCount} Ads",
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          child: isExpanded ? _SubjectAdsPreviewRow(subjectId: subject.id) : const SizedBox(width: double.infinity),
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
          error: (Object error, StackTrace stackTrace) => const Center(child: Text("Couldn't load this.")),
          data: (List<Ad> ads) {
            if (ads.isEmpty) {
              return const Center(child: Text("No one's sold this yet."));
            }
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: ads.length,
              itemBuilder: (BuildContext context, int index) {
                final Ad ad = ads[index];
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _AdThumbnail(
                    ad: ad,
                    width: 84,
                    onTap: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SubjectAdsViewerScreen(ads: ads, initialIndex: index),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AdThumbnail extends StatelessWidget {
  const _AdThumbnail({required this.ad, required this.width, required this.onTap});

  final Ad ad;
  final double width;
  final VoidCallback onTap;

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
            child: ad.thumbnailUrl != null
                ? CachedNetworkImage(imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover)
                : Container(color: Colors.black12),
          ),
        ),
      ),
    );
  }
}

import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../daily_ad/presentation/widgets/daily_ad_banner.dart";
import "../../../feed/domain/ad.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../providers/market_providers.dart";
import "search_screen.dart";

/// MARKET / Discovery (CLAUDE.md section 12) — "the market of ideas/Ads",
/// not a commerce marketplace.
class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text("Trending Subjects", style: Theme.of(context).textTheme.titleMedium),
          ),
          SizedBox(
            height: 44,
            child: trendingAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
              data: (List<AdSubject> subjects) => ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                itemCount: subjects.length,
                itemBuilder: (BuildContext context, int index) {
                  final AdSubject subject = subjects[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ActionChip(
                      label: Text("${subject.displayName.toUpperCase()}™"),
                      onPressed: () => unawaited(context.pushTo(RoutePaths.subjectOf(subject.id))),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text("Fresh Ads", style: Theme.of(context).textTheme.titleMedium),
          ),
          freshAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stackTrace) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text("$error"),
            ),
            data: (List<Ad> ads) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.sm),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 9 / 16,
              ),
              itemCount: ads.length,
              itemBuilder: (BuildContext context, int index) {
                final Ad ad = ads[index];
                return GestureDetector(
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SubjectAdsViewerScreen(ads: ads, initialIndex: index),
                      ),
                    ),
                  ),
                  child: ad.thumbnailUrl != null
                      ? CachedNetworkImage(imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover)
                      : Container(color: Colors.black12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

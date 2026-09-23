import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../create_ad/presentation/providers/create_ad_flow_controller.dart";
import "../../../feed/domain/ad.dart";
import "../../domain/subject_ads_sort.dart";
import "../providers/subject_providers.dart";
import "subject_ads_viewer_screen.dart";

/// AdSubject page (CLAUDE.md section 10): `SOCK™` / `84.2K Ads` header,
/// Trending/Top/New tabs, AD THIS SUBJECT.
class SubjectScreen extends ConsumerStatefulWidget {
  const SubjectScreen({required this.subjectId, super.key});

  final String subjectId;

  @override
  ConsumerState<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends ConsumerState<SubjectScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjectAsync = ref.watch(subjectByIdProvider(widget.subjectId));

    return Scaffold(
      appBar: AppBar(
        title: subjectAsync.when(
          data: (subject) => Text(subject == null ? "Subject" : "${subject.displayName.toUpperCase()}™"),
          loading: () => const Text("…"),
          error: (Object error, StackTrace stackTrace) => const Text("Subject"),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[Tab(text: "Trending"), Tab(text: "Top"), Tab(text: "New")],
        ),
      ),
      body: Column(
        children: <Widget>[
          subjectAsync.when(
            data: (subject) => subject == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text("${subject.adsCount} Ads", style: Theme.of(context).textTheme.bodyMedium),
                        FilledButton(
                          onPressed: () {
                            ref.read(createAdFlowControllerProvider.notifier).startWithSubject(subject);
                            context.goTo(RoutePaths.create);
                          },
                          child: const Text("AD THIS SUBJECT"),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _SubjectAdsGrid(subjectId: widget.subjectId, sort: SubjectAdsSort.trending),
                _SubjectAdsGrid(subjectId: widget.subjectId, sort: SubjectAdsSort.top),
                _SubjectAdsGrid(subjectId: widget.subjectId, sort: SubjectAdsSort.newest),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectAdsGrid extends ConsumerWidget {
  const _SubjectAdsGrid({required this.subjectId, required this.sort});

  final String subjectId;
  final SubjectAdsSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsAsync = ref.watch(subjectAdsProvider((subjectId, sort)));

    return adsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
      data: (List<Ad> ads) {
        if (ads.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text("No one's sold this yet."),
                SizedBox(height: AppSpacing.xs),
                Text("Be the first to advertise it.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return GridView.builder(
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
        );
      },
    );
  }
}

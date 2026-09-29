import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../../domain/ad.dart";
import "../providers/feed_providers.dart";

/// The AD THIS chain (CLAUDE.md section 9: "SEE IT → AD IT → ... THEY AD
/// IT"): every Ad someone made by pressing AD THIS on one Ad. Reached from
/// the "N made their own" line on the Ad.
class AdThisChainScreen extends ConsumerWidget {
  const AdThisChainScreen({required this.adId, super.key});

  final String adId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Ad>> childrenAsync = ref.watch(adThisChildrenProvider(adId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adThisChainTitle)),
      body: childrenAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(adThisChildrenProvider(adId)),
            child: Text(l10n.genericRetry),
          ),
        ),
        data: (List<Ad> ads) {
          if (ads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(l10n.adThisChainEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return GridView.builder(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 9 / 16,
            ),
            itemCount: ads.length,
            itemBuilder: (BuildContext context, int index) {
              final Ad ad = ads[index];
              return Semantics(
                button: true,
                label: "@${ad.creatorUsername ?? ""}",
                child: GestureDetector(
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SubjectAdsViewerScreen(ads: ads, initialIndex: index),
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (ad.thumbnailUrl != null)
                        CachedNetworkImage(imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover, memCacheWidth: 360)
                      else
                        const ColoredBox(color: Colors.black12),
                      Positioned(
                        left: AppSpacing.xs,
                        right: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: Text(
                          "@${ad.creatorUsername ?? ""}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            shadows: <Shadow>[Shadow(color: Colors.black87, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

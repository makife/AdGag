import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";

import "../../core/localization/generated/app_localizations.dart";

/// Shows [avatarUrl] large, in a circle, over a dimmed screen; a tap anywhere
/// (or back) closes it.
Future<void> showAvatarViewer(BuildContext context, String avatarUrl) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (BuildContext dialogContext, Animation<double> _, Animation<double> __) {
      final double size = (MediaQuery.sizeOf(dialogContext).shortestSide * 0.78).clamp(160, 360);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Center(
          child: Semantics(
            image: true,
            label: AppLocalizations.of(dialogContext).profilePhoto,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => SizedBox(
                  width: size,
                  height: size,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => SizedBox(
                  width: size,
                  height: size,
                  child: const Icon(Icons.person, size: 96, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (BuildContext _, Animation<double> animation, Animation<double> __, Widget child) {
      final Animation<double> curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(curved), child: child),
      );
    },
  );
}

/// [child] (an avatar) that opens [showAvatarViewer] when tapped — only when
/// there is a photo to show.
class TappableAvatar extends StatelessWidget {
  const TappableAvatar({required this.avatarUrl, required this.child, super.key});

  final String? avatarUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? url = avatarUrl;
    if (url == null || url.isEmpty) {
      return child;
    }
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).profilePhoto,
      child: GestureDetector(onTap: () => showAvatarViewer(context, url), child: child),
    );
  }
}

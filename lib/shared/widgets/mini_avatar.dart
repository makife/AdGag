import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";

import "../../core/theme/app_colors.dart";

/// Small circular profile picture next to a username (feed overlay,
/// reviews). No photo yet → the username's first letter on the brand
/// gradient, so it's never an empty circle.
class MiniAvatar extends StatelessWidget {
  const MiniAvatar({required this.avatarUrl, required this.username, this.size = 24, super.key});

  final String? avatarUrl;
  final String? username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String initial = (username == null || username!.isEmpty) ? "?" : username!.characters.first.toUpperCase();
    final Widget fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.45),
        ),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: avatarUrl == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(), // small decode, not the full photo
                placeholder: (BuildContext context, String url) => fallback,
                errorWidget: (BuildContext context, String url, Object error) => fallback,
              ),
      ),
    );
  }
}

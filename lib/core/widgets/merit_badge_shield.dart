import "package:flutter/material.dart";
import "../../data/models/merit_badge_def.dart";

/// Mirrors MeritBadgeShield.jsx — the one place any badge's artwork is
/// rendered. grayscale=true is used for not-yet-earned badges in the
/// catalog view, so it reads as "locked" at a glance.
class MeritBadgeShield extends StatelessWidget {
  const MeritBadgeShield({super.key, required this.badgeKey, this.size = 44, this.grayscale = false});

  final String badgeKey;
  final double size;
  final bool grayscale;

  @override
  Widget build(BuildContext context) {
    final path = kBadgeImagePaths[badgeKey];
    if (path == null) return SizedBox(width: size, height: size);
    final image = Image.asset(path, width: size, height: size, fit: BoxFit.contain);
    if (!grayscale) return image;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: Opacity(opacity: 0.75, child: image),
    );
  }
}

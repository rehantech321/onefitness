import "package:flutter/material.dart";
import "../../data/models/merit_badge_def.dart";
import "../theme/app_colors.dart";

/// Mirrors SubBadgeIcon.jsx — a circular sub-badge portrait (Gym Citizen's
/// 10 + Progress Tracker's 3), grayscaled and dimmed when not yet earned.
class SubBadgeIcon extends StatelessWidget {
  const SubBadgeIcon({super.key, required this.subBadgeKey, this.size = 44, this.earned = false});

  final String subBadgeKey;
  final double size;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final path = kSubBadgeImagePaths[subBadgeKey];
    if (path == null) return SizedBox(width: size, height: size);
    final image = ClipOval(
      child: Image.asset(path, width: size, height: size, fit: BoxFit.cover),
    );
    final decorated = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: earned ? AppColors.goldDim : AppColors.line, width: 1.5)),
      child: image,
    );
    if (earned) return decorated;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, -40,
        0.2126, 0.7152, 0.0722, 0, -40,
        0.2126, 0.7152, 0.0722, 0, -40,
        0, 0, 0, 1, 0,
      ]),
      child: decorated,
    );
  }
}

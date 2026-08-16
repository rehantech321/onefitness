import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/merit_badge_def.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors BadgeGallery.jsx — the full badge catalog, earned or not, with
/// what it takes to earn each one. Distinct from MeritBadgeRow (only shows
/// already-earned badges compactly).
class BadgeGalleryScreen extends ConsumerWidget {
  const BadgeGalleryScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnedBadges = ref.watch(earnedBadgesProvider);
    final earnedByKey = {
      for (final b in earnedBadges.where((b) => b.clientId == clientId && b.isActive)) b.badgeKey: b,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Merit Badges"),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
                children: [
                  TextSpan(
                    text: "Merit Badges recognize your consistency, progress, and involvement at One Fitness. Earn badges by completing challenges, tracking your progress, building healthy habits, and being an active part of our community. Collect five or more active Merit Badges to earn a +5 Merit Badge points bonus. ",
                  ),
                  TextSpan(text: "Automatic", style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  TextSpan(text: " badges are awarded by the app the moment you qualify. "),
                  TextSpan(text: "Coach Awarded", style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  TextSpan(text: " badges are given by your coach or the gym owner."),
                ],
              ),
            ),
          ),
          ...kMeritBadges.map((b) {
            final earned = earnedByKey[b.key];
            return AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      MeritBadgeShield(badgeKey: b.key, size: 56, grayscale: earned == null),
                      if (earned == null) const Icon(LucideIcons.lock, size: 16, color: Colors.white),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: earned != null ? AppColors.gold : AppColors.txt)),
                        Text(
                          b.category == "coach" ? "COACH AWARDED" : "AUTOMATIC",
                          style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(b.description, style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
                        if (earned != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text("Earned ${earned.earnedAt}", style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

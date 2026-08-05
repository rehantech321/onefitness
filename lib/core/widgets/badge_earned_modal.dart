import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../../data/models/merit_badge_def.dart";
import "app_buttons.dart";
import "merit_badge_shield.dart";

/// Mirrors BadgeEarnedModal.jsx — the celebration shown right after a
/// client earns a new badge.
class BadgeEarnedModal extends StatelessWidget {
  const BadgeEarnedModal({super.key, required this.badgeKey, this.method = "automatic", required this.onClose, this.onViewBadges});

  final String badgeKey;
  final String method;
  final VoidCallback onClose;
  final VoidCallback? onViewBadges;

  static Future<void> show(BuildContext context, {required String badgeKey, String method = "automatic", VoidCallback? onViewBadges}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => BadgeEarnedModal(
        badgeKey: badgeKey,
        method: method,
        onClose: () => Navigator.of(ctx).pop(),
        onViewBadges: onViewBadges == null
            ? null
            : () {
                Navigator.of(ctx).pop();
                onViewBadges();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = meritBadgeByKey(badgeKey);
    if (badge == null) return const SizedBox.shrink();
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("MERIT BADGE EARNED!", style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 14),
            MeritBadgeShield(badgeKey: badgeKey, size: 110),
            const SizedBox(height: 14),
            Text(badge.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.txt)),
            const SizedBox(height: 4),
            Text(
              method == "coach" ? "AWARDED BY YOUR COACH" : "EARNED AUTOMATICALLY",
              style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
            const SizedBox(height: 10),
            Text(badge.description, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5)),
            const SizedBox(height: 20),
            Row(
              children: [
                if (onViewBadges != null) ...[
                  Expanded(child: BtnGhost(onPressed: onViewBadges, child: const Text("View my badges"))),
                  const SizedBox(width: 8),
                ],
                Expanded(child: BtnGold(onPressed: onClose, child: const Text("Continue"))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "../../data/models/earned_badge.dart";
import "../../data/models/merit_badge_def.dart";
import "merit_badge_shield.dart";

/// Mirrors MeritBadgeRow.jsx — compact horizontal strip of a client's
/// ACTIVE (earned, not revoked) badges only.
class MeritBadgeRow extends StatelessWidget {
  const MeritBadgeRow({super.key, required this.clientId, required this.earnedBadges, this.size = 26});

  final String clientId;
  final List<EarnedBadge> earnedBadges;
  final double size;

  @override
  Widget build(BuildContext context) {
    final earnedKeys = earnedBadges.where((b) => b.clientId == clientId && b.isActive).map((b) => b.badgeKey).toSet();
    if (earnedKeys.isEmpty) return const SizedBox.shrink();
    final ordered = kMeritBadges.where((b) => earnedKeys.contains(b.key));
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: ordered.map((b) => Tooltip(message: b.name, child: MeritBadgeShield(badgeKey: b.key, size: size))).toList(),
    );
  }
}

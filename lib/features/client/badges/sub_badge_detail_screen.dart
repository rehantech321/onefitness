import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/earned_badge.dart";
import "../../../data/models/merit_badge_def.dart";

final _dateFmt = DateFormat("MMM d, yyyy");

String _fmtDate(String iso) => _dateFmt.format(DateTime.parse(iso));

/// Expiry is never stored — always earnedAt + 6 months, computed for
/// display only, same as the source's own fmtExpiry.
String _fmtExpiry(String earnedAtIso) {
  final d = DateTime.parse(earnedAtIso);
  return _dateFmt.format(DateTime(d.year, d.month + 6, d.day));
}

/// Mirrors SubBadgeDetailScreen.jsx — generic client-facing, read-only
/// sub-badge progress screen (Gym Citizen's 10, Progress Tracker's 3). A
/// client can see their own progress here but never check/uncheck
/// anything — that's the coach-only checklist, not built here.
class SubBadgeDetailScreen extends StatelessWidget {
  const SubBadgeDetailScreen({
    super.key,
    required this.clientId,
    required this.earnedBadges,
    required this.subBadges,
    required this.title,
    required this.blurb,
    required this.onBack,
  });

  final String clientId;
  final List<EarnedBadge> earnedBadges;
  final List<SubBadgeDef> subBadges;
  final String title;
  final String blurb;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final myBadges = earnedBadges.where((b) => b.clientId == clientId && b.isActive).toList();
    final byKey = {for (final b in myBadges) b.badgeKey: b};
    final activeCount = subBadges.where((s) => byKey.containsKey(s.key)).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: onBack,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.chevronLeft, size: 15),
            label: const Text("Merit Badges", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 10),
          SectionLabel("$title Progress: $activeCount/${subBadges.length}"),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(blurb, style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6)),
          ),
          ...subBadges.map((sub) {
            final earned = byKey[sub.key];
            return AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SubBadgeIcon(subBadgeKey: sub.key, size: 36, earned: earned != null),
                      if (earned == null) const Icon(LucideIcons.lock, size: 12, color: Colors.white),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: earned != null ? AppColors.gold : AppColors.txt)),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(sub.description, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.5)),
                        ),
                        if (earned != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "Earned ${_fmtDate(earned.earnedAt)} · expires ${_fmtExpiry(earned.earnedAt)}",
                              style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
                            ),
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

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/coach_merit_badge_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// This month's live progress toward each of the 6 rate-based Coach Merit
/// Badges (everything but Coach of the Month — see coach_merit_badge_utils.dart),
/// shown to the coach it belongs to. Shared by MyPayScreen and
/// CoachMeritBadgesScreen so both stay in sync with a single computation.
class CoachBadgeProgressList extends ConsumerWidget {
  const CoachBadgeProgressList({super.key, required this.coach});
  final Trainer coach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(trainerRosterProvider);
    final clientRecords = ref.watch(trainerClientRecordsProvider);
    final bookings = ref.watch(allBookingsProvider);
    final prEvents = ref.watch(coachPrEventsProvider);
    final challenges = ref.watch(challengesProvider);
    final settings = ref.watch(platformSettingsProvider);
    final badges = computeAllCoachBadges(
      coach: coach,
      roster: roster,
      clientRecords: clientRecords,
      bookings: bookings,
      prEvents: prEvents,
      challenges: challenges,
      range: presetRange("month"),
      habitPercent: settings.meritBadgeHabitPercent,
      habitConsecutiveWeeks: settings.meritBadgeHabitWeeks,
    );
    final rewardCentsByKey = {
      "full_house": settings.badgeFullHouseCents,
      "pr_factory": settings.badgePrFactoryCents,
      "check_in": settings.badgeCheckInCents,
      "comeback": settings.badgeComebackCents,
      "habit_coach": settings.badgeHabitCoachCents,
      "challenge_coach": settings.badgeChallengeCoachCents,
    };
    return Column(
      children: badges
          .map((b) => AppCard(
                borderColor: b.qualifies ? AppColors.gold : AppColors.line,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              CoachBadgeShield(badgeKey: b.badgeKey, size: 28, grayscale: !b.qualifies),
                              const SizedBox(width: 8),
                              Icon(b.qualifies ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 15, color: b.qualifies ? AppColors.gold : AppColors.mute),
                              const SizedBox(width: 6),
                              Text(b.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(
                          "\$${((rewardCentsByKey[b.badgeKey] ?? 0) / 100).toStringAsFixed(2)}",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(kCoachBadgeDescriptions[b.badgeKey] ?? "", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                    const SizedBox(height: 4),
                    Text(b.detail, style: const TextStyle(fontSize: 11, color: AppColors.txt)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

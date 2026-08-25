import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/coach_merit_badge_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../reports/date_range_filter.dart";
import "../reports/payroll_reports.dart";

String _payoutModeLabel(String mode) => switch (mode) {
      "perClient" => "per client",
      "perHour" => "per hour",
      _ => "per session",
    };

/// Mirrors MyPay.jsx — a coach's own read-only pay screen, scoped to their
/// commission rate and their own sessions in the selected range.
class MyPayScreen extends ConsumerStatefulWidget {
  const MyPayScreen({super.key});

  @override
  ConsumerState<MyPayScreen> createState() => _MyPayScreenState();
}

class _MyPayScreenState extends ConsumerState<MyPayScreen> {
  ReportRange _range = presetRange("month");

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final trainers = ref.watch(trainersProvider);
    final matches = trainers.where((t) => t.id == trainerAuth);
    if (matches.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "No pay data available."));
    final me = matches.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("My Pay"),
          AppCard(
            borderColor: AppColors.goldDim,
            child: Text(
              "You're paid ${_payoutModeLabel(me.payoutMode)} at \$${(me.payoutRateCents / 100).toStringAsFixed(2)}"
              "${me.referralCommissionPercent > 0 ? ', plus ${me.referralCommissionPercent}% on purchases by clients who used your Coach Code' : ''}.",
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
          DateRangeFilter(range: _range, onChange: (r) => setState(() => _range = r)),
          const SizedBox(height: 12),
          const SectionLabel("Commissions"),
          ServiceCommissionsReport(range: _range, onlyTrainerId: me.id),
          const SizedBox(height: 12),
          const SectionLabel("Payroll Summary"),
          PayrollSummaryReport(range: _range, onlyTrainerId: me.id),
          const SizedBox(height: 12),
          const SectionLabel("Merit Badge Earnings"),
          MeritBadgeEarningsReport(range: _range, onlyTrainerId: me.id),
          const SizedBox(height: 12),
          const SectionLabel("Coach Merit Badges — This Month"),
          const Text(
            "Automatic monthly coaching-performance incentives — finalized and paid out once the month ends.",
            style: TextStyle(fontSize: 11, color: AppColors.mute),
          ),
          const SizedBox(height: 8),
          _CoachBadgeProgressList(coach: me),
        ],
      ),
    );
  }
}

class _CoachBadgeProgressList extends ConsumerWidget {
  const _CoachBadgeProgressList({required this.coach});
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

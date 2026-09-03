import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/coach_merit_badge_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../reports/date_range_filter.dart";
import "../reports/payroll_reports.dart";
import "coach_badge_progress_list.dart";

/// A coach's own view of the Coach Merit Badge System — mirrors what
/// BadgeGalleryScreen gives clients for their (separate) client-facing merit
/// badges: what you have, what you don't yet, and exactly how to earn each
/// one. Distinct from My Pay's compact "this month" list — this screen adds
/// the how-it-works explanation, the Coach of the Month badge (which isn't
/// part of the 6 rate-based badges), and the full earned-badge history.
class CoachMeritBadgesScreen extends ConsumerStatefulWidget {
  const CoachMeritBadgesScreen({super.key});

  @override
  ConsumerState<CoachMeritBadgesScreen> createState() => _CoachMeritBadgesScreenState();
}

class _CoachMeritBadgesScreenState extends ConsumerState<CoachMeritBadgesScreen> {
  ReportRange _historyRange = presetRange("year");

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final trainers = ref.watch(trainersProvider);
    final matches = trainers.where((t) => t.id == trainerAuth);
    if (matches.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "No badge data available."));
    final me = matches.first;
    final settings = ref.watch(platformSettingsProvider);
    final coachOfMonthWins = ref.watch(coachMeritBadgesProvider).where((b) => b.trainerId == me.id && b.badgeKey == "coach_of_month").length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Merit Badges"),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              "Coach Merit Badges recognize your coaching performance, gym-wide, every month — session completion, PRs you log, following up with at-risk clients, habit consistency, and challenge participation. They're computed automatically from your activity, never set by hand, and finalized at month's end — the dollar reward you see is locked in the moment a badge is earned, so it never changes retroactively even if the owner updates reward values later. Earned rewards are added automatically to your pay.",
              style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
            ),
          ),
          const SectionLabel("This Month's Progress"),
          const SizedBox(height: 8),
          CoachBadgeProgressList(coach: me),
          const SizedBox(height: 8),
          AppCard(
            borderColor: coachOfMonthWins > 0 ? AppColors.gold : AppColors.line,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoachBadgeShield(badgeKey: "coach_of_month", size: 28, grayscale: coachOfMonthWins == 0),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Coach of the Month", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(
                            "\$${(settings.badgeCoachOfMonthCents / 100).toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(kCoachBadgeDescriptions["coach_of_month"] ?? "", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      const SizedBox(height: 4),
                      Text(
                        coachOfMonthWins > 0 ? "Won $coachOfMonthWins time${coachOfMonthWins == 1 ? '' : 's'} so far." : "Not won yet — decided automatically at month's end.",
                        style: const TextStyle(fontSize: 11, color: AppColors.txt),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel("Badge History"),
          DateRangeFilter(range: _historyRange, onChange: (r) => setState(() => _historyRange = r)),
          const SizedBox(height: 8),
          MeritBadgeEarningsReport(range: _historyRange, onlyTrainerId: me.id),
        ],
      ),
    );
  }
}

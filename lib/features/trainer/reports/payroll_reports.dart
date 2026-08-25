import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/coach_merit_badge_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

String _money(num v) => "\$${v.toStringAsFixed(2)}";

String _payoutRateLabel(Trainer t) {
  final rate = _money(t.payoutRateCents / 100);
  return switch (t.payoutMode) {
    "perClient" => "$rate/client",
    "perHour" => "$rate/hr",
    _ => "$rate/session",
  };
}

/// Mirrors PayrollReports.jsx's StaffHoursReport / ServiceCommissionsReport /
/// PayrollSummaryReport — all built on the shared `perTrainerInRange`
/// aggregation. `onlyTrainerId` scopes to one coach (used by My Pay).
class StaffHoursReport extends ConsumerWidget {
  const StaffHoursReport({super.key, required this.range, this.onlyTrainerId});
  final ReportRange range;
  final String? onlyTrainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = _trainers(ref, onlyTrainerId);
    final bookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final plans = ref.watch(membershipPlansProvider);
    final stats = perTrainerInRange(trainers, bookings, roster, plans, range)..sort((a, b) => b.sessionCount.compareTo(a.sessionCount));
    return _StatsTable(stats: stats, valueLabel: "Hours", valueOf: (s) => s.hours.toStringAsFixed(1));
  }
}

class ServiceCommissionsReport extends ConsumerWidget {
  const ServiceCommissionsReport({super.key, required this.range, this.onlyTrainerId});
  final ReportRange range;
  final String? onlyTrainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = _trainers(ref, onlyTrainerId);
    final bookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final plans = ref.watch(membershipPlansProvider);
    final stats = perTrainerInRange(trainers, bookings, roster, plans, range)..sort((a, b) => b.commission.compareTo(a.commission));
    return _StatsTable(stats: stats, valueLabel: "Pay", valueOf: (s) => _money(s.commission), extraLabel: "Rate", extraOf: (s) => _payoutRateLabel(s.trainer));
  }
}

class PayrollSummaryReport extends ConsumerWidget {
  const PayrollSummaryReport({super.key, required this.range, this.onlyTrainerId});
  final ReportRange range;
  final String? onlyTrainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = _trainers(ref, onlyTrainerId);
    final bookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final plans = ref.watch(membershipPlansProvider);
    final charges = ref.watch(chargesProvider);
    final coachBadges = ref.watch(coachMeritBadgesProvider);
    double totalPay(TrainerRangeStats s) => s.commission + referralCommissionInRange(charges, s.trainer.id, range) + meritBadgeEarningsInRange(coachBadges, s.trainer.id, range);
    final stats = perTrainerInRange(trainers, bookings, roster, plans, range).where((s) => s.sessionCount > 0 || totalPay(s) > 0).toList()
      ..sort((a, b) => totalPay(b).compareTo(totalPay(a)));
    return _StatsTable(
      stats: stats,
      valueLabel: "Pay owed",
      valueOf: (s) => _money(totalPay(s)),
      extras: [
        (
          label: "of which referrals",
          value: (s) {
            final referral = referralCommissionInRange(charges, s.trainer.id, range);
            return referral > 0 ? _money(referral) : "";
          },
        ),
        (
          label: "merit badges",
          value: (s) {
            final badges = meritBadgeEarningsInRange(coachBadges, s.trainer.id, range);
            return badges > 0 ? _money(badges) : "";
          },
        ),
      ],
    );
  }
}

/// Itemized Coach Merit Badge history for [onlyTrainerId] (or every coach,
/// owner view) in range — one row per finalized `coach_merit_badges` row,
/// plus a total. Registered in Reports Hub (owner) and embedded in My Pay
/// (coach self-view / owner viewing one coach).
class MeritBadgeEarningsReport extends ConsumerWidget {
  const MeritBadgeEarningsReport({super.key, required this.range, this.onlyTrainerId});
  final ReportRange range;
  final String? onlyTrainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = _trainers(ref, onlyTrainerId);
    final trainerIds = trainers.map((t) => t.id).toSet();
    final trainerNames = {for (final t in trainers) t.id: t.name};
    final months = <String>{};
    var d = DateTime(DateTime.parse(range.start).year, DateTime.parse(range.start).month, 1);
    final end = DateTime.parse(range.end);
    while (!d.isAfter(end)) {
      months.add("${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}");
      d = DateTime(d.year, d.month + 1, 1);
    }
    final rows = ref.watch(coachMeritBadgesProvider).where((b) => trainerIds.contains(b.trainerId) && months.contains(b.periodMonth)).toList()
      ..sort((a, b) => b.periodMonth.compareTo(a.periodMonth));
    if (rows.isEmpty) return const HintBox(text: "No merit badges finalized in this range.");
    final total = rows.fold(0.0, (sum, b) => sum + b.rewardCents / 100);
    return Column(
      children: [
        ...rows.map((b) => AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kCoachBadgeLabels[b.badgeKey] ?? b.badgeKey, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(
                          onlyTrainerId != null ? "${b.periodMonth} · ${b.payoutStatus}" : "${trainerNames[b.trainerId] ?? '—'} · ${b.periodMonth} · ${b.payoutStatus}",
                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  Text(_money(b.rewardCents / 100), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.gold)),
                ],
              ),
            )),
        AppCard(
          borderColor: AppColors.goldDim,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text(_money(total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}

List<Trainer> _trainers(WidgetRef ref, String? onlyTrainerId) {
  final all = ref.watch(trainersProvider);
  return onlyTrainerId == null ? all : all.where((t) => t.id == onlyTrainerId).toList();
}

typedef _ExtraLine = ({String label, String Function(TrainerRangeStats) value});

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.stats, required this.valueLabel, required this.valueOf, this.extraLabel, this.extraOf, this.extras = const []});
  final List<TrainerRangeStats> stats;
  final String valueLabel;
  final String Function(TrainerRangeStats) valueOf;

  /// Legacy single-breakout params — still supported for callers with just
  /// one line (e.g. StaffHoursReport's payout rate). Prefer [extras] for
  /// more than one. A blank value hides the line, same as an [extras] entry.
  final String? extraLabel;
  final String Function(TrainerRangeStats)? extraOf;

  /// Any number of "· label value" breakout lines, each independently
  /// hidden when its value comes back empty (e.g. no referral income this
  /// range) — generalizes the single extraLabel/extraOf pair above.
  final List<_ExtraLine> extras;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const HintBox(text: "No data for this range.");
    return Column(
      children: stats
          .map((s) {
            final parts = <String>[];
            if (extraLabel != null) {
              final extra = extraOf?.call(s);
              if (extra != null && extra.isNotEmpty) parts.add("$extraLabel $extra");
            }
            for (final e in extras) {
              final v = e.value(s);
              if (v.isNotEmpty) parts.add("${e.label} $v");
            }
            final suffix = parts.isEmpty ? "" : " · ${parts.join(' · ')}";
            return AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.trainer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text("${s.sessionCount} sessions$suffix", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(valueOf(s), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.gold)),
                        Text(valueLabel, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
                      ],
                    ),
                  ],
                ),
              );
          })
          .toList(),
    );
  }
}

/// Owner-only, opportunistic month finalization — see
/// SupabaseService.finalizeCoachBadgesForMonth's doc comment. Wraps a
/// child (Payroll Summary or the Coach Merit Badges report) and, once per
/// app session, finalizes last calendar month's Coach Merit Badges if
/// nothing's been finalized for it yet. Gated to owner-only by only ever
/// being mounted from ReportsHubScreen (itself owner-only) — never wrap a
/// coach-facing screen with this, or every coach's session would race to
/// finalize the same month concurrently.
class CoachMeritBadgeAutoFinalize extends ConsumerStatefulWidget {
  const CoachMeritBadgeAutoFinalize({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CoachMeritBadgeAutoFinalize> createState() => _CoachMeritBadgeAutoFinalizeState();
}

class _CoachMeritBadgeAutoFinalizeState extends ConsumerState<CoachMeritBadgeAutoFinalize> {
  static bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();
    if (!_checkedThisSession) {
      _checkedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFinalize());
    }
  }

  Future<void> _maybeFinalize() async {
    final now = DateTime.now();
    final lastMonthDate = DateTime(now.year, now.month - 1, 1);
    final periodMonth = "${lastMonthDate.year.toString().padLeft(4, '0')}-${lastMonthDate.month.toString().padLeft(2, '0')}";
    final existing = ref.read(coachMeritBadgesProvider);
    if (existing.any((b) => b.periodMonth == periodMonth)) return;
    final monthEnd = DateTime(now.year, now.month, 0);
    final monthRange = ReportRange(preset: "month", start: isoDate(lastMonthDate), end: isoDate(monthEnd));
    final settings = ref.read(platformSettingsProvider);
    try {
      await SupabaseService.finalizeCoachBadgesForMonth(
        periodMonth: periodMonth,
        monthRange: monthRange,
        coaches: ref.read(trainersProvider),
        roster: ref.read(trainerRosterProvider),
        clientRecords: ref.read(trainerClientRecordsProvider),
        bookings: ref.read(allBookingsProvider),
        prEvents: ref.read(coachPrEventsProvider),
        challenges: ref.read(challengesProvider),
        existingCoachBadges: existing,
        habitPercent: settings.meritBadgeHabitPercent,
        habitConsecutiveWeeks: settings.meritBadgeHabitWeeks,
        rewardCentsByBadgeKey: {
          "full_house": settings.badgeFullHouseCents,
          "pr_factory": settings.badgePrFactoryCents,
          "check_in": settings.badgeCheckInCents,
          "comeback": settings.badgeComebackCents,
          "habit_coach": settings.badgeHabitCoachCents,
          "challenge_coach": settings.badgeChallengeCoachCents,
          "coach_of_month": settings.badgeCoachOfMonthCents,
        },
      );
      final fresh = await SupabaseService.loadCoachMeritBadges();
      if (mounted) ref.read(coachMeritBadgesProvider.notifier).setAll(fresh);
    } catch (_) {
      // Opportunistic — a failure here just means we'll try again next
      // time this screen opens; never worth surfacing to the owner.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

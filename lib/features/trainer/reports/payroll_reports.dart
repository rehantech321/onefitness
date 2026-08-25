import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
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
    final stats = perTrainerInRange(trainers, bookings, roster, plans, range)
        .where((s) => s.sessionCount > 0 || s.commission > 0 || referralCommissionInRange(charges, s.trainer.id, range) > 0)
        .toList()
      ..sort((a, b) => (b.commission + referralCommissionInRange(charges, b.trainer.id, range)).compareTo(a.commission + referralCommissionInRange(charges, a.trainer.id, range)));
    return _StatsTable(
      stats: stats,
      valueLabel: "Pay owed",
      valueOf: (s) => _money(s.commission + referralCommissionInRange(charges, s.trainer.id, range)),
      extraLabel: "of which referrals",
      extraOf: (s) {
        final referral = referralCommissionInRange(charges, s.trainer.id, range);
        return referral > 0 ? _money(referral) : "";
      },
      hideExtraWhenEmpty: true,
    );
  }
}

List<Trainer> _trainers(WidgetRef ref, String? onlyTrainerId) {
  final all = ref.watch(trainersProvider);
  return onlyTrainerId == null ? all : all.where((t) => t.id == onlyTrainerId).toList();
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.stats, required this.valueLabel, required this.valueOf, this.extraLabel, this.extraOf, this.hideExtraWhenEmpty = false});
  final List<TrainerRangeStats> stats;
  final String valueLabel;
  final String Function(TrainerRangeStats) valueOf;
  final String? extraLabel;
  final String Function(TrainerRangeStats)? extraOf;

  /// When true, the "· extraLabel extraOf(s)" suffix is skipped entirely
  /// for a stat whose extraOf(s) comes back empty (e.g. no referral income
  /// this range) instead of showing "· of which referrals ".
  final bool hideExtraWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const HintBox(text: "No data for this range.");
    return Column(
      children: stats
          .map((s) {
            final extra = extraOf?.call(s);
            final showExtra = extraLabel != null && extra != null && !(hideExtraWhenEmpty && extra.isEmpty);
            return AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.trainer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text("${s.sessionCount} sessions${showExtra ? ' · $extraLabel $extra' : ''}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
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

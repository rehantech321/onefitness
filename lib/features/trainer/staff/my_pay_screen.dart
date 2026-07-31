import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../reports/date_range_filter.dart";
import "../reports/payroll_reports.dart";

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
            child: Text("Your commission rate is ${me.commissionRate}% of session revenue for the selected range.", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
          ),
          DateRangeFilter(range: _range, onChange: (r) => setState(() => _range = r)),
          const SizedBox(height: 12),
          const SectionLabel("Commissions"),
          ServiceCommissionsReport(range: _range, onlyTrainerId: me.id),
          const SizedBox(height: 12),
          const SectionLabel("Payroll Summary"),
          PayrollSummaryReport(range: _range, onlyTrainerId: me.id),
        ],
      ),
    );
  }
}

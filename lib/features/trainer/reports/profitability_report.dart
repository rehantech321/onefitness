import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

String _money(num v) => "\$${v.toStringAsFixed(2)}";

/// Mirrors ProfitabilityReport.jsx's RevenueVsPayrollReport.
class RevenueVsPayrollReport extends ConsumerWidget {
  const RevenueVsPayrollReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charges = revenueCharges(ref.watch(chargesProvider), range);
    final revenue = charges.fold<double>(0, (m, c) => m + (c.amount ?? 0));
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final plans = ref.watch(membershipPlansProvider);
    final payroll = perTrainerInRange(trainers, bookings, roster, plans, range).fold<double>(0, (m, s) => m + s.commission);
    final net = revenue - payroll;
    final margin = revenue > 0 ? (net / revenue * 1000).round() / 10 : 0.0;

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: DownloadCsvButton(
            filename: "revenue-vs-payroll.csv",
            rows: [
              ["Line item", "Amount"],
              ["Revenue (charges logged in range)", _money(revenue)],
              ["Payroll (commission owed in range)", _money(-payroll)],
              ["Net profit ($margin% margin)", _money(net)],
            ],
          ),
        ),
        AppCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Revenue", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text(_money(revenue), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.grn))])),
        AppCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Payroll", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text("-${_money(payroll)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.danger))])),
        AppCard(
          borderColor: AppColors.goldDim,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Net profit ($margin% margin)", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text(_money(net), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: net >= 0 ? AppColors.grn : AppColors.danger)),
            ],
          ),
        ),
      ],
    );
  }
}

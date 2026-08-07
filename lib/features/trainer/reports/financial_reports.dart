import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

String _money(num v) => "\$${v.toStringAsFixed(2)}";

/// Mirrors FinancialReports.jsx's ItemizedSalesReport — every real charge
/// in range, newest first, with a total row.
class ItemizedSalesReport extends ConsumerWidget {
  const ItemizedSalesReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charges = revenueCharges(ref.watch(chargesProvider), range);
    if (charges.isEmpty) return const HintBox(text: "No sales in this range.");
    final total = charges.fold<double>(0, (m, c) => m + (c.amount ?? 0));
    return Column(
      children: [
        ...charges.map((c) => AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text("${c.description ?? c.planName ?? '—'} · ${c.category ?? ''} · ${c.date}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  Text(_money(c.amount ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.gold)),
                ],
              ),
            )),
        AppCard(
          borderColor: AppColors.goldDim,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total", style: TextStyle(fontWeight: FontWeight.w800)), Text(_money(total), style: const TextStyle(fontWeight: FontWeight.w800))]),
        ),
      ],
    );
  }
}

/// Mirrors FinancialReports.jsx's RealTimeChargesReport — reverse-chron
/// charge feed with Refund/Waive actions, both real owner-only Edge
/// Function calls (refund-charge issues an actual Stripe refund in this
/// project's test-mode Stripe key; waive-charge marks a fee waived).
class RealTimeChargesReport extends ConsumerStatefulWidget {
  const RealTimeChargesReport({super.key, required this.range});
  final ReportRange range;

  @override
  ConsumerState<RealTimeChargesReport> createState() => _RealTimeChargesReportState();
}

class _RealTimeChargesReportState extends ConsumerState<RealTimeChargesReport> {
  String? _busyId;

  Future<void> _refresh() async {
    final fresh = await SupabaseService.loadCharges();
    ref.read(chargesProvider.notifier).setAll(fresh);
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final charges = revenueCharges(ref.watch(chargesProvider), widget.range);
    if (charges.isEmpty) return const HintBox(text: "No charges in this range.");
    return Column(
      children: charges
          .map((c) => AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${c.clientName} · ${_money(c.amount ?? 0)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text("${c.description ?? '—'} · ${c.date}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    if (c.type == "purchase")
                      TextButton(
                        onPressed: _busyId != null
                            ? null
                            : () async {
                                setState(() => _busyId = c.id);
                                try {
                                  await SupabaseService.refundCharge(c.id);
                                  await _refresh();
                                } catch (e) {
                                  _showError(e.toString().replaceFirst("Exception: ", ""));
                                } finally {
                                  if (mounted) setState(() => _busyId = null);
                                }
                              },
                        child: Text(_busyId == c.id ? "Refunding…" : "Refund", style: const TextStyle(fontSize: 11, color: Color(0xFFC97F7F))),
                      )
                    else if (c.type == "early_termination_fee")
                      c.waivedAt != null
                          ? const Text("Waived", style: TextStyle(fontSize: 11, color: AppColors.mute))
                          : TextButton(
                              onPressed: _busyId != null
                                  ? null
                                  : () async {
                                      setState(() => _busyId = c.id);
                                      try {
                                        await SupabaseService.waiveCharge(c.id);
                                        await _refresh();
                                      } catch (e) {
                                        _showError(e.toString().replaceFirst("Exception: ", ""));
                                      } finally {
                                        if (mounted) setState(() => _busyId = null);
                                      }
                                    },
                              child: Text(_busyId == c.id ? "Waiving…" : "Waive", style: const TextStyle(fontSize: 11, color: AppColors.gold)),
                            ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// Mirrors FinancialReports.jsx's ProjectedRevenueReport — current active
/// members grouped by plan, monthly revenue for subscription plans.
class ProjectedRevenueReport extends ConsumerWidget {
  const ProjectedRevenueReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(trainerRosterProvider);
    final plansNotifier = ref.watch(membershipPlansProvider.notifier);
    final byPlan = <String, int>{};
    for (final c in roster) {
      final plan = plansNotifier.byId(c.membershipPlanId);
      if (plan == null || plan.kind == PlanKind.program) continue;
      byPlan[plan.id] = (byPlan[plan.id] ?? 0) + 1;
    }
    if (byPlan.isEmpty) return const HintBox(text: "No active members on a billed plan.");
    var totalMonthly = 0.0;
    final rows = byPlan.entries.map((e) {
      final plan = plansNotifier.byId(e.key)!;
      final monthly = plan.kind == PlanKind.membership ? (plan.priceCents / 100 * e.value) : 0.0;
      totalMonthly += monthly;
      return (plan, e.value, monthly);
    }).toList();

    return Column(
      children: [
        ...rows.map((r) => AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$1.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text("${r.$1.kind == PlanKind.membership ? 'Membership' : 'Package'} · ${r.$2} active client${r.$2 == 1 ? '' : 's'}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  Text(r.$3 > 0 ? "${_money(r.$3)}/mo" : "—", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.gold)),
                ],
              ),
            )),
        AppCard(
          borderColor: AppColors.goldDim,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Monthly total", style: TextStyle(fontWeight: FontWeight.w800)), Text("${_money(totalMonthly)}/mo", style: const TextStyle(fontWeight: FontWeight.w800))]),
        ),
      ],
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/rewards_domain.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors RewardsReport.jsx — the owner's view of the Rewards & Points
/// ledger: issued/redeemed/expired/voided totals, a by-source breakdown,
/// and discretionary grants broken out per coach with their stated reasons.
/// Deliberately no dollar figure anywhere — the ledger only ever stores
/// POINTS; the dollar value of a past redemption depended on that
/// checkout's price at the time, which isn't persisted point-in-time-
/// accurately enough to re-derive here.
class RewardsPointsReport extends ConsumerWidget {
  const RewardsPointsReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(pointsLedgerProvider);
    final trainers = ref.watch(trainersProvider);
    final inWindow = ledger.where((r) => range.includes(r.createdAt.substring(0, 10))).toList();

    final issued = inWindow.where((r) => r.amount > 0).fold<int>(0, (s, r) => s + r.amount);
    final redeemed = inWindow.where((r) => r.type == "redeem").fold<int>(0, (s, r) => s + r.amount.abs());
    final expired = inWindow.where((r) => r.type == "expire").fold<int>(0, (s, r) => s + r.amount.abs());
    final voided = inWindow.where((r) => r.type == "void").fold<int>(0, (s, r) => s + r.amount.abs());

    final bySource = <String, (int points, int count)>{};
    for (final r in inWindow) {
      final cur = bySource[r.source] ?? (0, 0);
      bySource[r.source] = (cur.$1 + r.amount, cur.$2 + 1);
    }
    final sourceRows = bySource.entries.toList()..sort((a, b) => b.value.$1.abs().compareTo(a.value.$1.abs()));

    final staffNames = {for (final t in trainers) t.id: t.name};
    String nameFor(String? id) => id == null ? "Owner" : (staffNames[id] ?? "Owner");

    final grantsByCoach = <String, (String coach, int points, int count, List<String> reasons)>{};
    for (final r in inWindow) {
      if (r.type != "grant" || r.source != "discretionary_grant") continue;
      final key = r.grantedByUserId ?? "unknown";
      final cur = grantsByCoach[key] ?? (nameFor(r.grantedByUserId), 0, 0, <String>[]);
      final reasons = [...cur.$4, if (r.reason != null && r.reason!.isNotEmpty) r.reason!];
      grantsByCoach[key] = (cur.$1, cur.$2 + r.amount, cur.$3 + 1, reasons);
    }
    final grantRows = grantsByCoach.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            _StatTile(label: "Issued", value: issued),
            _StatTile(label: "Redeemed", value: redeemed),
            _StatTile(label: "Expired", value: expired),
            _StatTile(label: "Voided/Deducted", value: voided),
          ],
        ),
        const SizedBox(height: 18),
        const Text("BY SOURCE", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 8),
        if (sourceRows.isEmpty)
          const HintBox(text: "No points activity in this range.")
        else
          ...sourceRows.map((e) => AppCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(sourceLabel(e.key), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    Text("${e.value.$1 > 0 ? '+' : ''}${e.value.$1} pts", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.gold)),
                    const SizedBox(width: 10),
                    Text("${e.value.$2} row${e.value.$2 == 1 ? '' : 's'}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                  ],
                ),
              )),
        const SizedBox(height: 18),
        const Text("DISCRETIONARY GRANTS BY COACH", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 8),
        if (grantRows.isEmpty)
          const HintBox(text: "No discretionary grants in this range.")
        else
          ...grantRows.map((g) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(g.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text("${g.$3} grant${g.$3 == 1 ? '' : 's'} · +${g.$2} pts", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
                      ],
                    ),
                    if (g.$4.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...g.$4.map((reason) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text("• $reason", style: const TextStyle(fontSize: 12, color: AppColors.txt, height: 1.5)),
                          )),
                    ],
                  ],
                ),
              )),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("$value", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.gold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../utils/rewards_domain.dart";
import "../../data/models/points_ledger_entry.dart";
import "app_card.dart";
import "hint_box.dart";

/// Mirrors rewards/LedgerTable.jsx — shared by the client's Rewards screen
/// and the coach's Points tab: date/action/points/running-balance rows,
/// newest first. `onVoid`/`canVoid` are optional — only PointsTab passes
/// them, giving staff an inline Void button clients never see.
class LedgerTable extends StatelessWidget {
  const LedgerTable({
    super.key,
    required this.rows,
    this.showGrantedBy = false,
    this.staffNames = const {},
    this.emptyText = "No points activity yet.",
    this.onVoid,
    this.canVoid,
  });

  final List<PointsLedgerEntry> rows;
  final bool showGrantedBy;
  final Map<String, String> staffNames;
  final String emptyText;
  final void Function(PointsLedgerEntry)? onVoid;
  final bool Function(PointsLedgerEntry)? canVoid;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return HintBox(text: emptyText);

    final sorted = [...rows]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var running = 0;
    final withBalance = sorted.map((r) {
      running += r.amount;
      return (row: r, balance: running);
    }).toList();
    final newestFirst = withBalance.reversed.toList();

    return Column(
      children: newestFirst.map((entry) {
        final r = entry.row;
        final positive = r.amount > 0;
        final showVoidBtn = onVoid != null && canVoid != null && canVoid!(r);
        return AppCard(
          margin: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sourceLabel(r.source), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.txt)),
                    Text(
                      [
                        r.createdAt,
                        if (showGrantedBy && r.grantedByUserId != null) "By ${staffNames[r.grantedByUserId] ?? 'staff'}",
                        if (showGrantedBy && r.reason != null) "\"${r.reason}\"",
                      ].join(" · "),
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
              if (showVoidBtn)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => onVoid!(r),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                    child: const Text("Void", style: TextStyle(fontSize: 11)),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${positive ? '+' : ''}${r.amount}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: positive ? AppColors.success : AppColors.danger)),
                  Text("Bal: ${entry.balance}", style: const TextStyle(fontSize: 10, color: AppColors.mute)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

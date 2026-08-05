import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/points_ledger_utils.dart";
import "../../../core/utils/rewards_domain.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/points_ledger_entry.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors PointsTab.jsx — coach/owner client-profile tab (More → Points).
/// Grant buttons (+1/+3/+5), an owner-only Deduct action, and the full
/// ledger with an owner-only Void button per row. The source's 5/month
/// coach cap and 24h void window are both server-side rules with no
/// client-side enforcement here either, same trust posture as elsewhere.
class PointsTab extends ConsumerStatefulWidget {
  const PointsTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends ConsumerState<PointsTab> {
  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == widget.clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final info = matches.first;
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    final staffNames = {for (final t in trainers) t.id: t.name};

    final ledger = ref.watch(pointsLedgerProvider);
    final myLedger = ledger.where((l) => l.clientId == widget.clientId).toList();
    final replay = replayLedger(myLedger);
    final expiringSoon = expiringWithin(replay.lots, days: kRewardExpiringSoonDays);
    final expiringPoints = expiringSoon.fold<int>(0, (s, l) => s + l.remaining);

    void grant(int amount) async {
      final reason = await _askReason(context, "+$amount grant");
      if (reason == null) return;
      ref.read(pointsLedgerProvider.notifier).add(PointsLedgerEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            clientId: widget.clientId,
            amount: amount,
            type: "grant",
            source: "discretionary_grant",
            createdAt: DateTime.now().toIso8601String().substring(0, 10),
            expiresAt: DateTime.now().add(const Duration(days: 180)).toIso8601String().substring(0, 10),
            grantedByUserId: trainerAuth,
            reason: reason,
          ));
    }

    void deduct() async {
      final amountStr = await _promptText(context, "Deduct how many points from ${info.name}? (current balance: ${replay.balance})");
      if (amountStr == null || !context.mounted) return;
      final amount = int.tryParse(amountStr.trim());
      if (amount == null || amount <= 0) return;
      final reason = await _askReason(context, "deduction");
      if (reason == null) return;
      ref.read(pointsLedgerProvider.notifier).add(PointsLedgerEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            clientId: widget.clientId,
            amount: -amount,
            type: "deduct",
            source: "owner_deduction",
            createdAt: DateTime.now().toIso8601String().substring(0, 10),
            grantedByUserId: trainerAuth,
            reason: reason,
          ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Points — ${info.name}"),
          AppCard(
            child: Row(
              children: [
                Text("${replay.balance}", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.gold)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Current balance", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                      if (expiringSoon.isNotEmpty) Text("$expiringPoints expiring soon", style: const TextStyle(fontSize: 11, color: AppColors.warning)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel("Grant points"),
          AppCard(
            child: Row(
              children: [1, 3, 5].map((amt) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: amt == 5 ? 0 : 8),
                    child: OutlinedButton(
                      onPressed: () => grant(amt),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold), padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: Text("+$amt", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (!isOwner) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text("Capped at 5 points per client per month for coaches — the owner has no cap.", style: TextStyle(fontSize: 11, color: AppColors.mute))),
          if (isOwner) ...[
            OutlinedButton(
              onPressed: deduct,
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), side: const BorderSide(color: Color(0xFF6B3B3B)), minimumSize: const Size.fromHeight(44)),
              child: const Text("Deduct points"),
            ),
            const SizedBox(height: 12),
          ],
          const SectionLabel("History"),
          LedgerTable(
            rows: myLedger,
            showGrantedBy: true,
            staffNames: staffNames,
            emptyText: "No points activity for this client yet.",
            canVoid: (row) => isOwner && (row.type == "earn" || row.type == "grant"),
            onVoid: (row) async {
              final reason = await _askReason(context, "void");
              if (reason == null) return;
              ref.read(pointsLedgerProvider.notifier).add(PointsLedgerEntry(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    clientId: widget.clientId,
                    amount: -row.amount,
                    type: "void",
                    source: "void_grant",
                    createdAt: DateTime.now().toIso8601String().substring(0, 10),
                    grantedByUserId: trainerAuth,
                    reason: reason,
                    voidedByLedgerId: row.id,
                  ));
            },
          ),
        ],
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String verb) async {
  final reason = await _promptText(context, "Reason for this $verb (required, at least 5 characters):");
  if (reason == null) return null;
  if (reason.trim().length < 5) return null;
  return reason.trim();
}

Future<String?> _promptText(BuildContext context, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      content: AppField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("OK")),
      ],
    ),
  );
}

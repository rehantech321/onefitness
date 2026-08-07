import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/points_ledger_utils.dart";
import "../../../core/utils/rewards_domain.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors RewardsScreen.jsx — balance, an expiry banner, a simplified
/// redeem action (the source's Stripe-subscription-vs-not branching is
/// backend-driven; here redeeming just writes a `redemption_balance`
/// ledger row), the static "Ways to Earn" list, and the full ledger.
class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _redeeming = false;

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(pointsLedgerProvider);
    final myLedger = ledger.where((l) => l.clientId == widget.clientId).toList();
    final replay = replayLedger(myLedger);
    final expiringSoon = expiringWithin(replay.lots, days: kRewardExpiringSoonDays);
    final expiringPoints = expiringSoon.fold<int>(0, (s, l) => s + l.remaining);
    final earliestExpiry = expiringSoon.isEmpty ? null : (expiringSoon.map((l) => l.expiresAt!).toList()..sort()).first;
    final redemptionPlan = planRedemption(replay.lots, capPoints: kRewardMaxRedeemPoints, minPoints: kRewardMinRedeemPoints);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.gold.withValues(alpha: 0.12), Colors.transparent]),
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.gift, size: 26, color: AppColors.gold),
                const SizedBox(height: 6),
                Text("${replay.balance}", style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.gold)),
                const Text("REWARD POINTS", style: TextStyle(fontSize: 12, color: AppColors.mute, letterSpacing: 1)),
              ],
            ),
          ),
          if (expiringSoon.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: kPointsBannerExpiring.bg, border: Border.all(color: kPointsBannerExpiring.border), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Text(kPointsBannerExpiring.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$expiringPoints point${expiringPoints == 1 ? '' : 's'} expiring by ${earliestExpiry ?? ''}",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPointsBannerExpiring.color),
                    ),
                  ),
                ],
              ),
            ),
          const SectionLabel("Redeem"),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Redeeming applies a discount toward your next purchase or renewal. Each point stays available for 6 months from the day you earned it.",
                  style: TextStyle(fontSize: 12, color: AppColors.txt, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (redemptionPlan != null)
                  BtnGold(
                    full: true,
                    onPressed: _redeeming
                        ? null
                        : () async {
                            setState(() => _redeeming = true);
                            try {
                              await SupabaseService.redeemPoints(widget.clientId);
                              final fresh = await SupabaseService.loadPointsLedgerFor(widget.clientId);
                              ref.read(pointsLedgerProvider.notifier).replaceForClient(widget.clientId, fresh);
                              setState(() => _redeeming = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Points redeemed — the discount will apply to your next bill.")));
                              }
                            } catch (e) {
                              setState(() => _redeeming = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
                              }
                            }
                          },
                    child: Text(_redeeming ? "Redeeming…" : "Redeem ${redemptionPlan.points} points now"),
                  )
                else
                  Text("You need at least $kRewardMinRedeemPoints points to redeem (up to $kRewardMaxRedeemPoints at once).", style: const TextStyle(fontSize: 13, color: AppColors.mute)),
              ],
            ),
          ),
          const SectionLabel("Ways to earn"),
          AppCard(
            child: Column(
              children: kWaysToEarn.asMap().entries.map((entry) {
                final w = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(border: entry.key == kWaysToEarn.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
                  child: Row(
                    children: [
                      SizedBox(width: 34, child: Text("+${w.points}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.txt)),
                            Text(w.desc, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SectionLabel("History"),
          LedgerTable(rows: myLedger, emptyText: "No points activity yet — see Ways to Earn above to get started."),
        ],
      ),
    );
  }
}

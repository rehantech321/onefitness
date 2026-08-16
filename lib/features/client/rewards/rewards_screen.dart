import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/points_ledger_utils.dart";
import "../../../core/utils/rewards_domain.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/merit_badge_def.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors RewardsScreen.jsx — balance, an expiry banner, a real redeem
/// action (branches on whether this client has an active Stripe
/// subscription, same as the source: an active subscriber redeems
/// immediately via a Stripe balance credit, everyone else just flips a
/// flag applied automatically at their next purchase), a Merit Badges
/// progress card, the static "Ways to Earn" list, and the full ledger.
class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key, required this.clientId, this.onOpenBadges});

  final String clientId;
  final VoidCallback? onOpenBadges;

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _redeeming = false;
  bool _togglingFlag = false;

  Future<void> _redeemNow() async {
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
  }

  Future<void> _toggleRedeemFlag(bool next) async {
    setState(() => _togglingFlag = true);
    try {
      await SupabaseService.updateClientRow(widget.clientId, redeemPointsNextRenewal: next);
      ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(redeemPointsNextRenewal: next));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
      }
    } finally {
      if (mounted) setState(() => _togglingFlag = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final earnedBadges = ref.watch(earnedBadgesProvider);
    final ledger = ref.watch(pointsLedgerProvider);
    final myLedger = ledger.where((l) => l.clientId == widget.clientId).toList();
    final replay = replayLedger(myLedger);
    final expiringSoon = expiringWithin(replay.lots, days: kRewardExpiringSoonDays);
    final expiringPoints = expiringSoon.fold<int>(0, (s, l) => s + l.remaining);
    final earliestExpiry = expiringSoon.isEmpty ? null : (expiringSoon.map((l) => l.expiresAt!).toList()..sort()).first;
    final redemptionPlan = planRedemption(replay.lots, capPoints: kRewardMaxRedeemPoints, minPoints: kRewardMinRedeemPoints);

    // Only a real top-level Merit Badge counts here — Gym Citizen's 10
    // coach-checked sub-badges aren't in kMeritBadges, so this exclusion
    // falls out of the catalog lookup for free (see merit_badge_def.dart).
    final knownKeys = kMeritBadges.map((b) => b.key).toSet();
    final activeBadgeCount = earnedBadges
        .where((b) => b.clientId == widget.clientId && b.isActive && knownKeys.contains(b.badgeKey))
        .map((b) => b.badgeKey)
        .toSet()
        .length;
    final badgesEarned = activeBadgeCount >= kMeritBadgeMinActiveForPoints;
    final badgesRemaining = kMeritBadgeMinActiveForPoints - activeBadgeCount;

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
                  "Turn the toggle on to use your points toward your next purchase or renewal automatically. Leave it off to keep accumulating points — each point stays available for 6 months from the day you earned it.",
                  style: TextStyle(fontSize: 12, color: AppColors.txt, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (redemptionPlan != null)
                  if (info.stripeSubscriptionId != null) ...[
                    _ToggleRow(
                      label: "Redeem ${redemptionPlan.points} points now",
                      hint: "Applies a discount off your next bill immediately — your subscription is already active, so this can't wait for a future renewal the way a new purchase can.",
                      value: false,
                      onChanged: (next) {
                        if (next && !_redeeming) _redeemNow();
                      },
                    ),
                    if (_redeeming) const Padding(padding: EdgeInsets.only(top: 6), child: Text("Redeeming…", style: TextStyle(fontSize: 12, color: AppColors.gold))),
                  ] else
                    _ToggleRow(
                      label: "Redeem ${redemptionPlan.points} points on my next purchase",
                      hint: "Applies automatically as a discount at checkout.",
                      value: info.redeemPointsNextRenewal,
                      onChanged: _togglingFlag ? null : _toggleRedeemFlag,
                    )
                else
                  Text("You need at least $kRewardMinRedeemPoints points to redeem (up to $kRewardMaxRedeemPoints at once).", style: const TextStyle(fontSize: 13, color: AppColors.mute)),
              ],
            ),
          ),
          const SectionLabel("Merit Badges"),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badgesEarned
                                ? (activeBadgeCount == kMeritBadgeMinActiveForPoints
                                    ? "$activeBadgeCount of $kMeritBadgeMinActiveForPoints Merit Badges"
                                    : "$activeBadgeCount Active Merit Badges")
                                : "$activeBadgeCount of $kMeritBadgeMinActiveForPoints required badges",
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.txt),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              badgesEarned
                                  ? (activeBadgeCount == kMeritBadgeMinActiveForPoints
                                      ? "+$kMeritBadgeBonusPoints Points Earned"
                                      : "+$kMeritBadgeBonusPoints Merit Badge Points")
                                  : "Earn $badgesRemaining more Merit Badge${badgesRemaining == 1 ? "" : "s"} to receive +$kMeritBadgeBonusPoints points.",
                              style: TextStyle(fontSize: 12, fontWeight: badgesEarned ? FontWeight.w700 : FontWeight.w400, color: badgesEarned ? AppColors.grn : AppColors.mute),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (earnedBadges.any((b) => b.clientId == widget.clientId && b.isActive)) ...[
                  const SizedBox(height: 12),
                  MeritBadgeRow(clientId: widget.clientId, earnedBadges: earnedBadges),
                ],
                if (widget.onOpenBadges != null)
                  Padding(
                    padding: EdgeInsets.only(top: earnedBadges.any((b) => b.clientId == widget.clientId && b.isActive) ? 10 : 12),
                    child: InkWell(
                      onTap: widget.onOpenBadges,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("See all Merit Badges", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
                            SizedBox(width: 4),
                            Icon(LucideIcons.chevronRight, size: 13, color: AppColors.gold),
                          ],
                        ),
                      ),
                    ),
                  ),
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

/// Mirrors FormPrimitives.jsx `ToggleRow` — a full-width tappable row with a
/// label/hint and a toggle icon on the right, instead of a native Switch
/// (matches the source's own custom look).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, this.hint, required this.value, required this.onChanged});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.txt)),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              value ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
              size: 28,
              color: value ? AppColors.gold : AppColors.mute,
            ),
          ],
        ),
      ),
    );
  }
}

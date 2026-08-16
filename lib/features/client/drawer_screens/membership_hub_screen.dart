import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../dashboard/sessions_remaining_badge.dart";

/// Mirrors MembershipsHub.jsx — current plan status (reusing the same badge
/// shown on the Dashboard), plan details, browse-and-buy for a client with
/// no plan yet, and — new here — Change Plan (real Stripe proration or a
/// scheduled switch at next renewal) and Cancel Membership (with an
/// early-termination-fee preview) for a client who already has one.
/// Trimmed vs. the web app: no referral-email capture and no card/ACH
/// choice (this app is card-only) — both scoped out in Part 8.
class MembershipHubScreen extends ConsumerStatefulWidget {
  const MembershipHubScreen({super.key});

  @override
  ConsumerState<MembershipHubScreen> createState() => _MembershipHubScreenState();
}

class _MembershipHubScreenState extends ConsumerState<MembershipHubScreen> {
  String? _busyPlanId;
  String? _error;
  bool _browsing = false;
  String? _timingChoicePlanId;
  bool _cancelBusy = false;
  Map<String, dynamic>? _cancelPreview; // {feeCents, renewsAt, noticeDaysRequired}, awaiting confirm

  Future<void> _buy(String clientId, MembershipPlan plan) async {
    setState(() {
      _busyPlanId = plan.id;
      _error = null;
    });
    try {
      if (plan.priceCents <= 0) {
        // Free plan — no Stripe involved, matches MembershipsHub.jsx's own
        // direct-assign path for a $0 plan.
        await SupabaseService.updateClientRow(clientId, membershipPlanId: plan.id);
        ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(membershipPlanId: plan.id));
      } else {
        final returnUrl = Uri.base.origin + Uri.base.path;
        final url = await SupabaseService.createCheckoutSession(planId: plan.id, returnUrl: returnUrl);
        // "_self" — a full same-tab redirect to Stripe's hosted page, same
        // as the web app's own `window.location.href = url` (a new-tab
        // popup would leave the "return" landing in a tab the client isn't
        // looking at).
        await launchUrl(Uri.parse(url), webOnlyWindowName: "_self");
      }
      if (mounted) setState(() => _browsing = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  /// A real prorated/scheduled CHANGE only makes sense paid-subscription ->
  /// paid-subscription while a real Stripe subscription already exists —
  /// anything else (switching to/from a one-time package, a free plan, or
  /// having nothing yet) has no billing cycle to prorate or schedule
  /// against, so it falls back to plain cancel-then-checkout instead.
  bool _isRealChange(ClientInfo info, MembershipPlan p) =>
      info.stripeSubscriptionId != null && p.priceCents > 0 && effectivePaymentType(p) == "subscription";

  Future<void> _selectPlanForSwitch(ClientInfo info, MembershipPlan p) async {
    if (_isRealChange(info, p)) {
      setState(() => _timingChoicePlanId = p.id);
      return;
    }
    // Switching off a plan with a real active Stripe subscription must
    // cancel that subscription first — otherwise the old subscription
    // keeps billing every month behind the client's back.
    if (info.stripeSubscriptionId != null) {
      setState(() {
        _busyPlanId = p.id;
        _error = null;
      });
      try {
        await SupabaseService.cancelMembership();
        ref.read(clientInfoProvider.notifier).update(
              (i) => i.copyWith(clearMembershipPlanId: true, clearStripeSubscriptionId: true, clearPendingPlan: true),
            );
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e.toString().replaceFirst("Exception: ", "");
            _busyPlanId = null;
          });
        }
        return;
      }
    }
    await _buy(info.id, p);
  }

  Future<void> _confirmTiming(ClientInfo info, MembershipPlan p, String timing) async {
    setState(() {
      _busyPlanId = p.id;
      _error = null;
    });
    try {
      final result = await SupabaseService.changeMembershipPlan(newPlanId: p.id, timing: timing);
      if (timing == "immediate") {
        ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(membershipPlanId: p.id, clearPendingPlan: true));
      } else {
        ref.read(clientInfoProvider.notifier).update(
              (i) => i.copyWith(pendingPlanId: p.id, pendingPlanEffectiveAt: result["effectiveAt"] as String?),
            );
      }
      if (mounted) {
        setState(() {
          _timingChoicePlanId = null;
          _browsing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _cancelBusy = true;
      _error = null;
    });
    try {
      final preview = await SupabaseService.cancelMembership(preview: true);
      final feeCents = (preview["feeCents"] as num?)?.toInt() ?? 0;
      if (feeCents > 0) {
        if (mounted) setState(() => _cancelPreview = preview);
        return;
      }
      await SupabaseService.cancelMembership();
      ref.read(clientInfoProvider.notifier).update(
            (i) => i.copyWith(clearMembershipPlanId: true, clearStripeSubscriptionId: true, clearPendingPlan: true),
          );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _confirmCancelWithFee() async {
    setState(() {
      _cancelBusy = true;
      _error = null;
    });
    try {
      await SupabaseService.cancelMembership();
      ref.read(clientInfoProvider.notifier).update(
            (i) => i.copyWith(clearMembershipPlanId: true, clearStripeSubscriptionId: true, clearPendingPlan: true),
          );
      if (mounted) setState(() => _cancelPreview = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plans = ref.watch(membershipPlansProvider);
    final plansNotifier = ref.watch(membershipPlansProvider.notifier);
    final plan = plansNotifier.byId(info.membershipPlanId);
    final pendingPlan = info.pendingPlanId != null ? plansNotifier.byId(info.pendingPlanId) : null;
    final buyable = plans.where((p) => !p.archived && p.kind != PlanKind.program).toList();

    if (_cancelPreview != null) {
      final feeCents = (_cancelPreview!["feeCents"] as num?)?.toInt() ?? 0;
      final renewsAt = _cancelPreview!["renewsAt"] as String?;
      final noticeDays = (_cancelPreview!["noticeDaysRequired"] as num?)?.toInt() ?? 0;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("Early Termination Fee"),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0x1AC9784A),
                border: Border.all(color: const Color(0xFFA8632F)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Canceling now is inside the $noticeDays-day notice window before your renewal"
                "${renewsAt != null ? " on $renewsAt" : ""} — a \$${(feeCents / 100).toStringAsFixed(2)} early termination fee applies. "
                "It'll be logged for your gym to collect.",
                style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelBusy ? null : _confirmCancelWithFee,
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line), foregroundColor: const Color(0xFFC97F7F), padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: Text(_cancelBusy ? "Working…" : "Cancel anyway", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelBusy ? null : () => setState(() => _cancelPreview = null),
                    style: OutlinedButton.styleFrom(backgroundColor: AppColors.gold.withValues(alpha: 0.12), side: const BorderSide(color: AppColors.goldDim), foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: const Text("Keep my plan", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_timingChoicePlanId != null) {
      final p = plansNotifier.byId(_timingChoicePlanId);
      if (p == null) return const SizedBox.shrink();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel("Switch to ${p.name}"),
            const HintBox(text: "Your card isn't charged an extra full price — switching now prorates the difference onto your next invoice."),
            const SizedBox(height: 16),
            AppCard(
              onTap: _busyPlanId != null ? null : () => _confirmTiming(info, p, "immediate"),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Switch now", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text("Takes effect immediately. A prorated charge or credit for the difference appears on your next invoice.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  ),
                ],
              ),
            ),
            AppCard(
              onTap: _busyPlanId != null ? null : () => _confirmTiming(info, p, "end_of_cycle"),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Switch at my next renewal", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text("Keep your current plan until then — no change, no proration, until it switches automatically.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("⚠ $_error", style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _busyPlanId != null ? null : () => setState(() => _timingChoicePlanId = null),
              style: TextButton.styleFrom(foregroundColor: AppColors.mute, alignment: Alignment.centerLeft),
              child: Text(_busyPlanId != null ? "Working…" : "Cancel"),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Your Membership"),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text("⚠ $_error", style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (plan != null && !_browsing) ...[
            SessionsRemainingBadge(info: info, bookings: bookings),
            if (pendingPlan != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  "Switching to ${pendingPlan.name}${info.pendingPlanEffectiveAt != null ? " on ${info.pendingPlanEffectiveAt}" : ""}.",
                  style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 4),
            SectionLabel("Plan Details"),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: "Plan", value: plan.name),
                  _DetailRow(label: "Type", value: plan.kind == PlanKind.membership ? "Membership" : (plan.kind == PlanKind.package ? "Package" : "Program")),
                  if (plan.maxSessions != null && plan.maxSessions! > 0)
                    _DetailRow(
                      label: "Sessions",
                      value: "${plan.maxSessions} ${plan.kind == PlanKind.membership ? "per month" : "total"}",
                    ),
                  if (plan.allowedTypes.isNotEmpty)
                    _DetailRow(label: "Covers", value: plan.allowedTypes.map((t) => t == "semi-private" ? "Semi-Private" : "One-on-One").join(", ")),
                  if (plan.termMonths != null) _DetailRow(label: "Term", value: "${plan.termMonths} months, auto-renews"),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelBusy ? null : () => setState(() => _browsing = true),
                    style: OutlinedButton.styleFrom(backgroundColor: AppColors.gold.withValues(alpha: 0.12), side: const BorderSide(color: AppColors.goldDim), foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: const Text("Change plan", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelBusy ? null : _cancel,
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line), foregroundColor: const Color(0xFFC97F7F), padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: Text(_cancelBusy ? "Working…" : "Cancel", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (plan == null)
              const HintBox(text: "You don't have a membership yet. Choose a plan below to get started.")
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionLabel("Switch Plan"),
                  TextButton(
                    onPressed: () => setState(() => _browsing = false),
                    style: TextButton.styleFrom(foregroundColor: AppColors.mute),
                    child: const Text("Back", style: TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            if (buyable.isNotEmpty) ...[
              if (plan == null) ...[
                const SizedBox(height: 14),
                const SectionLabel("Available Plans"),
              ],
              ...buyable.map((p) {
                final isCurrent = plan != null && p.id == plan.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    borderColor: isCurrent ? AppColors.gold : null,
                    child: Opacity(
                      opacity: isCurrent ? 0.75 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                              Text(
                                p.priceCents > 0 ? "\$${(p.priceCents / 100).toStringAsFixed(2)}${p.kind == PlanKind.membership ? '/mo' : ''}" : "Free",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.gold),
                              ),
                            ],
                          ),
                          if (p.maxSessions != null && p.maxSessions! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                "${p.maxSessions} sessions ${p.kind == PlanKind.membership ? "per month" : "total"}",
                                style: const TextStyle(fontSize: 12, color: AppColors.mute),
                              ),
                            ),
                          const SizedBox(height: 10),
                          if (isCurrent)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                              child: const Text("Current plan", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.mute)),
                            )
                          else
                            BtnGold(
                              full: true,
                              onPressed: _busyPlanId != null ? null : () => plan != null ? _selectPlanForSwitch(info, p) : _buy(info.id, p),
                              child: Text(
                                _busyPlanId == p.id
                                    ? "Working…"
                                    : plan != null
                                        ? (p.priceCents > 0 ? "Switch to this plan" : "Switch — no charge")
                                        : (p.priceCents > 0 ? "Subscribe — redirects to secure checkout" : "Start free plan"),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.mute)),
          Text(value, style: const TextStyle(fontSize: 13, color: AppColors.txt, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

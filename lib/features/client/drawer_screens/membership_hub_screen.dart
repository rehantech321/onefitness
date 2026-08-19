import "package:flutter/foundation.dart" show kIsWeb;
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
/// no plan yet, and three self-service actions for a client who already
/// has one: Change Access (real Stripe proration, a billing-cycle reset,
/// or a scheduled switch at next renewal), Pause Access (the same real
/// freeze/unfreeze mechanism the coach-side client-profile screen already
/// uses, opened up to client self-service), and Cancel (schedules the real
/// Stripe subscription to end at the close of the current billing period —
/// access and billing both run through what's already paid for; no fee,
/// no refund).
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
  String _typeFilter = "all"; // all | membership | package
  String? _timingChoicePlanId;
  String? _prorateChoicePlanId;
  bool _cancelBusy = false;
  bool _pauseBusy = false;

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
        // Uri.base.origin only resolves on Flutter web (the native build's
        // Uri.base is a non-http asset path and throws on `.origin`) — on
        // mobile, send the app's own custom-scheme deep link instead, so
        // the browser hands control back to the app once Stripe redirects
        // (see AndroidManifest.xml/Info.plist's "onefitness://checkout-return"
        // intent filter and main.dart's _AppLinksListener). Either way the
        // plan is only ever granted by stripe-webhook, never by this
        // "return" landing itself.
        final returnUrl = kIsWeb ? Uri.base.origin + Uri.base.path : "onefitness://checkout-return";
        final url = await SupabaseService.createCheckoutSession(planId: plan.id, returnUrl: returnUrl);
        // "_self" — a full same-tab redirect to Stripe's hosted page, same
        // as the web app's own `window.location.href = url` (a new-tab
        // popup would leave the "return" landing in a tab the client isn't
        // looking at). On mobile this opens the external browser instead.
        await launchUrl(Uri.parse(url), webOnlyWindowName: "_self", mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
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
      if (timing == "end_of_cycle") {
        ref.read(clientInfoProvider.notifier).update(
              (i) => i.copyWith(pendingPlanId: p.id, pendingPlanEffectiveAt: result["effectiveAt"] as String?),
            );
      } else {
        ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(membershipPlanId: p.id, clearPendingPlan: true));
      }
      if (mounted) {
        setState(() {
          _timingChoicePlanId = null;
          _prorateChoicePlanId = null;
          _browsing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  Future<void> _startCancel() async {
    setState(() {
      _cancelBusy = true;
      _error = null;
    });
    Map<String, dynamic> preview;
    try {
      preview = await SupabaseService.cancelMembership(preview: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst("Exception: ", "");
          _cancelBusy = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _cancelBusy = false);
    if (!mounted) return;
    final periodEndsAt = preview["periodEndsAt"] as String?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Cancel your membership?", style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          "Access continues through ${periodEndsAt ?? 'the end of your current billing period'}. After that date: any bookings scheduled "
          "beyond it are cancelled, you won't be able to book new sessions past it, and unused sessions aren't carried over. There's no refund, "
          "and this can't be undone.",
          style: const TextStyle(color: AppColors.mute, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.mute),
            child: const Text("Never mind"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)),
            child: const Text("Cancel at end of billing period", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _cancelBusy = true;
      _error = null;
    });
    try {
      final result = await SupabaseService.cancelMembership();
      ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(membershipCancelsAt: result["cancelsAt"] as String?));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _openPauseSheet(ClientInfo info) async {
    String? start;
    String? end;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          Future<void> pickDate(bool isStart) async {
            final now = DateTime.now();
            final picked = await showDatePicker(context: sheetCtx, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 3));
            if (picked == null) return;
            final iso = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
            setSheetState(() {
              if (isStart) {
                start = iso;
              } else {
                end = iso;
              }
            });
          }

          Widget dateField(String label, String? value, VoidCallback onTap) => FieldLabeled(
                label: label,
                child: InkWell(
                  onTap: onTap,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                    ),
                    child: Text(value ?? "Select date", style: TextStyle(fontSize: 14, color: value == null ? AppColors.mute : AppColors.txt)),
                  ),
                ),
              );

          return Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sheetCtx).viewInsets.bottom + 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Pause Access", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.txt)),
                const SizedBox(height: 6),
                const Text(
                  "Your access is fully paused for this window; billing pauses too and resumes automatically when it ends.",
                  style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
                ),
                const SizedBox(height: 16),
                dateField("Start date", start, () => pickDate(true)),
                const SizedBox(height: 10),
                dateField("End date", end, () => pickDate(false)),
                const SizedBox(height: 16),
                BtnGold(
                  full: true,
                  onPressed: (start != null && end != null) ? () => Navigator.of(sheetCtx).pop(true) : null,
                  child: const Text("Pause my access"),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed == true && start != null && end != null) {
      await _confirmPause(info, start!, end!);
    }
  }

  Future<void> _confirmPause(ClientInfo info, String start, String end) async {
    setState(() {
      _pauseBusy = true;
      _error = null;
    });
    try {
      await SupabaseService.freezeMembership(info.id, start, end);
      ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(membershipPaused: true, membershipPausedAt: start, membershipFreezeEndsAt: end));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _pauseBusy = false);
    }
  }

  Future<void> _resumeAccess(ClientInfo info) async {
    setState(() {
      _pauseBusy = true;
      _error = null;
    });
    try {
      await SupabaseService.unfreezeMembership(info.id);
      ref.read(clientInfoProvider.notifier).update(
            (i) => i.copyWith(membershipPaused: false, clearMembershipPausedAt: true, clearMembershipFreezeEndsAt: true),
          );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _pauseBusy = false);
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
    final filteredBuyable = _typeFilter == "all" ? buyable : buyable.where((p) => p.kind.name == _typeFilter).toList();
    final cancelPending = info.membershipCancelsAt != null;

    if (_prorateChoicePlanId != null) {
      final p = plansNotifier.byId(_prorateChoicePlanId);
      if (p == null) return const SizedBox.shrink();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel("Switch to ${p.name} now"),
            const HintBox(text: "Choose how you'd like to handle the cost of switching today."),
            const SizedBox(height: 16),
            AppCard(
              onTap: _busyPlanId != null ? null : () => _confirmTiming(info, p, "immediate"),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Prorate the difference", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      "Switches now. A prorated charge or credit for the difference appears on your next invoice — your renewal date doesn't change.",
                      style: TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  ),
                ],
              ),
            ),
            AppCard(
              onTap: _busyPlanId != null ? null : () => _confirmTiming(info, p, "immediate_reset"),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Reset my billing cycle to start today", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      "You're charged the new plan's full price today, and your next renewal resets to one cycle from today.",
                      style: TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
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
              onPressed: _busyPlanId != null ? null : () => setState(() => _prorateChoicePlanId = null),
              style: TextButton.styleFrom(foregroundColor: AppColors.mute, alignment: Alignment.centerLeft),
              child: Text(_busyPlanId != null ? "Working…" : "Back"),
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
            const HintBox(text: "Your card isn't charged an extra full price — switching now prorates the difference onto your next invoice, unless you choose to reset your cycle instead."),
            const SizedBox(height: 16),
            AppCard(
              onTap: _busyPlanId != null
                  ? null
                  : () {
                      if (p.priceCents > 0 && p.kind == PlanKind.membership) {
                        setState(() => _prorateChoicePlanId = p.id);
                      } else {
                        _confirmTiming(info, p, "immediate");
                      }
                    },
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Switch now", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text("Takes effect immediately.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
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
            if (cancelPending)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0x1AC97F7F), border: Border.all(color: const Color(0xFFA8632F)), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  "Membership ends on ${info.membershipCancelsAt}. You'll keep access until then.",
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC97F7F), fontWeight: FontWeight.w600),
                ),
              )
            else if (info.membershipPaused)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  "Paused${info.membershipFreezeEndsAt != null ? " until ${info.membershipFreezeEndsAt}" : ""}.",
                  style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600),
                ),
              )
            else if (pendingPlan != null)
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
            if (!cancelPending) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelBusy || _pauseBusy ? null : () => setState(() => _browsing = true),
                      style: OutlinedButton.styleFrom(backgroundColor: AppColors.gold.withValues(alpha: 0.12), side: const BorderSide(color: AppColors.goldDim), foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text("Change Access", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelBusy || _pauseBusy
                          ? null
                          : () => info.membershipPaused ? _resumeAccess(info) : _openPauseSheet(info),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line), foregroundColor: AppColors.txt, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: Text(
                        _pauseBusy ? "Working…" : (info.membershipPaused ? "Resume Access" : "Pause Access"),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelBusy || _pauseBusy ? null : _startCancel,
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line), foregroundColor: const Color(0xFFC97F7F), padding: const EdgeInsets.symmetric(vertical: 5)),
                  child: Text(_cancelBusy ? "Working…" : "Cancel", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ] else ...[
            if (plan == null)
              const HintBox(text: "You don't have a membership yet. Choose a plan below to get started.")
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionLabel("Change Access"),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  _TypeFilterChip(label: "All", selected: _typeFilter == "all", onTap: () => setState(() => _typeFilter = "all")),
                  const SizedBox(width: 8),
                  _TypeFilterChip(label: "Memberships", selected: _typeFilter == "membership", onTap: () => setState(() => _typeFilter = "membership")),
                  const SizedBox(width: 8),
                  _TypeFilterChip(label: "Packages", selected: _typeFilter == "package", onTap: () => setState(() => _typeFilter = "package")),
                ],
              ),
              const SizedBox(height: 12),
              if (filteredBuyable.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: HintBox(text: "No plans match this filter."),
                ),
              ...filteredBuyable.map((p) {
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

class _TypeFilterChip extends StatelessWidget {
  const _TypeFilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.transparent,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute)),
      ),
    );
  }
}

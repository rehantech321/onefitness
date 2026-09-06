import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/client_plan.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../dashboard/sessions_remaining_badge.dart";

/// Mirrors MembershipsHub.jsx — current plan status (reusing the same badge
/// shown on the Dashboard), plan details, browse-and-buy for a client with
/// no plan yet, and two self-service actions for a client who already has
/// one: Change Access (real Stripe proration, a billing-cycle reset, or a
/// scheduled switch at next renewal) and Cancel (schedules the real Stripe
/// subscription to end at the close of the current billing period — access
/// and billing both run through what's already paid for; no fee, no
/// refund). Pausing/freezing is deliberately NOT self-service here — that
/// stays coach/owner-only (see freeze-membership/unfreeze-membership's own
/// server-side role check, and the coach-side client-profile screen) — a
/// paused client only ever sees a read-only status banner and a pointer to
/// ask their coach.
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
  bool _catalog = false;
  final _couponController = TextEditingController();

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _buy(String clientId, MembershipPlan plan) async {
    final couponCode = _couponController.text.trim();
    if (couponCode.isNotEmpty && ref.read(couponsProvider.notifier).byCode(couponCode) == null) {
      setState(() => _error = "That coupon code isn't valid or is no longer active.");
      return;
    }
    setState(() {
      _busyPlanId = plan.id;
      _error = null;
    });
    try {
      if (plan.priceCents <= 0) {
        // Free plan — no Stripe involved. Goes through the server rather
        // than writing the row directly: `plans` is a grant (it unlocks
        // intake forms), so client-side writes to it are reverted by
        // prevent_membership_self_grant.
        await SupabaseService.enrollFreePlan(plan.id, clientId: clientId);
        final enrollment = ClientPlanEnrollment(
          planId: plan.id,
          status: "active",
          startDate: isoToday(),
          termMonths: plan.termMonths,
        );
        ref.read(clientInfoProvider.notifier).update(
              (i) => i.copyWith(
                // A program sits alongside the membership rather than
                // replacing it — mirrors what the server just did.
                membershipPlanId: isProgramKind(plan.kind) ? i.membershipPlanId : plan.id,
                plans: [...i.plans.where((e) => e.planId != plan.id), enrollment],
              ),
            );
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
        final url = await SupabaseService.createCheckoutSession(
          planId: plan.id,
          returnUrl: returnUrl,
          couponCode: couponCode.isEmpty ? null : couponCode,
        );
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
    final periodEndsAt = (preview["periodEndsAt"] ?? preview["renewsAt"]) as String?;
    // A free plan, a one-time package, or a coach-assigned plan has no
    // billing period to run out, so there's nothing to schedule — it ends
    // the moment they confirm. Saying "access continues through <date>" for
    // one of those would be a straight-up lie, so both the wording and the
    // confirm button change to match what will actually happen.
    final immediate = preview["immediate"] == true || periodEndsAt == null;
    final currentPlan = ref.read(membershipPlansProvider.notifier).byId(ref.read(clientInfoProvider).membershipPlanId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          immediate ? "Cancel your ${currentPlan?.name ?? "plan"}?" : "Cancel your membership?",
          style: const TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          immediate
              ? "This ends now — you'll lose access straight away, any bookings you already have are cancelled, and unused sessions aren't carried "
                  "over. There's no refund, and this can't be undone."
              : "Access continues through $periodEndsAt. After that date: any bookings scheduled beyond it are cancelled, you won't be able to "
                  "book new sessions past it, and unused sessions aren't carried over. There's no refund, and this can't be undone.",
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
            child: Text(
              immediate ? "Cancel it now" : "Cancel at end of billing period",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
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
      final cancelsAt = result["cancelsAt"] as String?;
      ref.read(clientInfoProvider.notifier).update(
            (i) => cancelsAt != null
                ? i.copyWith(membershipCancelsAt: cancelsAt)
                // Cancelled outright — drop the plan locally too, so the
                // screen doesn't keep showing a plan the server just removed.
                : i.copyWith(clearMembershipPlanId: true, clearStripeSubscriptionId: true, clearPendingPlan: true),
          );
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
    // "Change Access" is about swapping the plan that grants gym access, so
    // it lists memberships and packages only. Programs are bought alongside
    // access rather than instead of it — they live in the Membership Hub
    // catalogue (see the _catalog branch), which is also where a client with
    // no membership at all is sent to get started.
    final buyable = plans.where((p) => !p.archived && !isProgramKind(p.kind)).toList();
    final filteredBuyable = _typeFilter == "all" ? buyable : buyable.where((p) => p.kind.name == _typeFilter).toList();
    final cancelPending = info.membershipCancelsAt != null;

    if (_prorateChoicePlanId != null) {
      final p = plansNotifier.byId(_prorateChoicePlanId);
      if (p == null) return const SizedBox.shrink();
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _prorateChoicePlanId = null),
        child: SingleChildScrollView(
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
        ),
      );
    }

    if (_catalog) {
      final current = plansNotifier.byId(info.membershipPlanId);
      // Everything the gym offers, not just what's switchable — including
      // programs, which aren't self-serve purchases today. Showing them
      // (clearly marked) is the point of this screen: a client asking
      // "what else could I do here?" gets a real answer instead of a list
      // silently filtered down to what the checkout happens to support.
      final visible = plans.where((p) => !p.archived && p.public).toList()
        ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _catalog = false),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BackBar(onBack: () => setState(() => _catalog = false), title: "Your Membership"),
              const SizedBox(height: 10),
              const SectionLabel("All Access Options"),
              const SizedBox(height: 8),
              const HintBox(text: "Everything ONE Fitness offers. Your current plan is highlighted."),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const HintBox(text: "No plans are published yet — ask your coach what's available.")
              else
                for (final p in visible) ...[
                  _CatalogCard(
                    plan: p,
                    isCurrent: current != null && p.id == current.id,
                    held: info.plans.any((e) => e.planId == p.id && e.status == "active"),
                    busy: _busyPlanId != null,
                    onSelect: () {
                      setState(() => _catalog = false);
                      // A program is an addition, never a switch — buying one
                      // must not disturb the membership that drives sessions
                      // and billing. Only access plans go through the
                      // switch/proration flow.
                      if (isProgramKind(p.kind) || current == null) {
                        _buy(info.id, p);
                      } else {
                        _selectPlanForSwitch(info, p);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              if (_error != null)
                Text("⚠ $_error", style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    if (_timingChoicePlanId != null) {
      final p = plansNotifier.byId(_timingChoicePlanId);
      if (p == null) return const SizedBox.shrink();
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _timingChoicePlanId = null),
        child: SingleChildScrollView(
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
        ),
      );
    }

    return LocalBackScope(
      isOpen: _browsing,
      onBack: () => setState(() => _browsing = false),
      child: SingleChildScrollView(
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
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelBusy ? null : () => setState(() => _browsing = true),
                  style: OutlinedButton.styleFrom(backgroundColor: AppColors.gold.withValues(alpha: 0.12), side: const BorderSide(color: AppColors.goldDim), foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: const Text("Change Access", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 8),
              // Sits between Change Access and Cancel on purpose: browsing
              // everything on offer is a lighter, more common thing to want
              // than either committing to a switch or giving the plan up.
              // "Change Access" only lists what this client can switch to;
              // this shows the whole catalogue, programs included.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelBusy ? null : () => setState(() => _catalog = true),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.goldDim), foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: const Text("Membership Hub", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 8),
              // Pausing/freezing a membership is coach/owner-only — see
              // freeze-membership/unfreeze-membership's own server-side
              // role check. No self-service action here; just a pointer to
              // who can actually do it, so a paused client isn't left
              // wondering how to resume.
              if (info.membershipPaused)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    "Your access is paused by your coach or ONE Fitness — ask them to resume it.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelBusy ? null : _startCancel,
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
              FieldLabeled(
                label: "Coupon code (optional)",
                child: AppField(
                  controller: _couponController,
                  placeholder: "Enter a code",
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              Builder(builder: (context) {
                final entered = _couponController.text.trim();
                if (entered.isEmpty) return const SizedBox(height: 12);
                final match = ref.watch(couponsProvider.notifier).byCode(entered);
                return Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: Text(
                    match != null ? "✓ ${match.valueLabel} will be applied at checkout." : "No active coupon matches that code.",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: match != null ? AppColors.success : AppColors.mute),
                  ),
                );
              }),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text("⚠ $_error", style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12, fontWeight: FontWeight.w700)),
                ),
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
      ),
    );
  }
}

/// One row of the "All Access Options" catalogue. A program has no
/// self-serve purchase path, so it's shown for information with a pointer to
/// the coach rather than a button that would go nowhere.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.plan,
    required this.isCurrent,
    required this.held,
    required this.busy,
    required this.onSelect,
  });

  final MembershipPlan plan;

  /// This is the client's current access plan (their membership/package).
  final bool isCurrent;

  /// Already enrolled — true for programs they've bought, which they keep
  /// while also holding a membership.
  final bool held;
  final bool busy;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final isProgram = isProgramKind(plan.kind);
    final kindLabel = planKindLabel(plan.kind);
    return AppCard(
      borderColor: isCurrent ? AppColors.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              const SizedBox(width: 8),
              Text(
                plan.priceCents > 0
                    ? "\$${(plan.priceCents / 100).toStringAsFixed(2)}${plan.kind == PlanKind.membership ? '/mo' : ''}"
                    : "Free",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              kindLabel,
              if ((plan.maxSessions ?? 0) > 0)
                "${plan.maxSessions} sessions ${plan.kind == PlanKind.membership ? "per month" : "total"}",
              if (plan.allowedTypes.isNotEmpty)
                plan.allowedTypes.map((t) => t == "semi-private" ? "Semi-Private" : "One-on-One").join(", "),
            ].join(" · "),
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
          const SizedBox(height: 10),
          if (isCurrent || held)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(8)),
              child: Text(
                isCurrent ? "Your current plan" : "Active",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold),
              ),
            )
          else
            BtnGold(
              full: true,
              onPressed: busy ? null : onSelect,
              child: Text(
                plan.priceCents > 0
                    // A program is bought in addition to whatever access the
                    // client already has, so "Add" rather than "Choose" —
                    // "Choose this plan" would imply giving up their
                    // membership, which is exactly what it doesn't do.
                    ? (isProgram ? "Add this program" : "Choose this plan")
                    : (isProgram ? "Add this program" : "Start free plan"),
              ),
            ),
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

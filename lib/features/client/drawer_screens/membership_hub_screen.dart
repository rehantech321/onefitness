import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../dashboard/sessions_remaining_badge.dart";

/// Mirrors MembershipsHub.jsx — current plan status (reusing the same badge
/// shown on the Dashboard), plan details, and — new here — real
/// browse-and-buy for a client with no plan yet, via real Stripe Checkout.
/// Switching/cancelling an EXISTING paid plan needs cancel-membership
/// called first (see MembershipsHub.jsx's own stripeSubscriptionId check)
/// to avoid leaving an old subscription still billing behind the client's
/// back — that's real complexity for its own pass, so for now (matching
/// the hint text below) that path still goes through the gym directly.
class MembershipHubScreen extends ConsumerStatefulWidget {
  const MembershipHubScreen({super.key});

  @override
  ConsumerState<MembershipHubScreen> createState() => _MembershipHubScreenState();
}

class _MembershipHubScreenState extends ConsumerState<MembershipHubScreen> {
  String? _busyPlanId;
  String? _error;

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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plans = ref.watch(membershipPlansProvider);
    final plan = ref.watch(membershipPlansProvider.notifier).byId(info.membershipPlanId);
    final buyable = plans.where((p) => !p.archived && p.kind != PlanKind.program).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Your Membership"),
          SessionsRemainingBadge(info: info, bookings: bookings),
          if (plan != null) ...[
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.info, size: 15, color: AppColors.mute),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "To change or cancel your plan, reach out to your gym directly.",
                      style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const HintBox(text: "You don't have a membership yet. Choose a plan below to get started."),
            if (buyable.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionLabel("Available Plans"),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
                ),
              ...buyable.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
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
                          BtnGold(
                            full: true,
                            onPressed: _busyPlanId != null ? null : () => _buy(info.id, p),
                            child: Text(_busyPlanId == p.id ? "Starting checkout…" : (p.priceCents > 0 ? "Subscribe — redirects to secure checkout" : "Start free plan")),
                          ),
                        ],
                      ),
                    ),
                  )),
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

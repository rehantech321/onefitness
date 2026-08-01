import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/mock/mock_data.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../dashboard/sessions_remaining_badge.dart";

/// Mirrors MembershipsHub.jsx, trimmed to the read side: current plan status
/// (reusing the same badge shown on the Dashboard) and plan details.
/// Browsing/purchasing other plans goes through Stripe Checkout in the web
/// app — out of scope until real payments are wired up here.
class MembershipHubScreen extends ConsumerWidget {
  const MembershipHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plan = MockData.planById(info.membershipPlanId);

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
          ] else
            const HintBox(text: "You don't have a membership yet. Visit the front desk or ask your coach to get started."),
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

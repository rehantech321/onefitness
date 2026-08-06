import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors MembershipsHub.jsx `SessionsRemainingBadge`. Returns nothing
/// (SizedBox.shrink) if the client has no membership plan, matching the
/// React component's `return null`.
class SessionsRemainingBadge extends ConsumerWidget {
  const SessionsRemainingBadge({super.key, required this.info, required this.bookings});

  final ClientInfo info;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(membershipPlansProvider.notifier).byId(info.membershipPlanId);
    if (plan == null) return const SizedBox.shrink();

    if (info.membershipPaused) {
      return AppCard(
        borderColor: const Color(0xFFA8632F),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.circleSlash, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${plan.name} — Frozen",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Contact your gym to unfreeze early — nothing on your plan has been lost.",
              style: TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ],
        ),
      );
    }

    if (plan.kind == PlanKind.program || plan.maxSessions == null || plan.maxSessions == 0) {
      final active = info.plans.where((p) => p.planId == plan.id && p.status == "active").toList();
      final enrollment = active.isNotEmpty ? active.first : null;
      final term = (enrollment != null && plan.termMonths != null)
          ? termRenewal(enrollment.startDate, plan.termMonths!)
          : null;
      return AppCard(
        borderColor: AppColors.goldDim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "YOUR MEMBERSHIP",
              style: TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.clipboardList, size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Your coach builds and manages your program.",
              style: TextStyle(fontSize: 12, color: AppColors.mute),
            ),
            if (term != null) ...[
              const SizedBox(height: 6),
              Text(
                "${term.termMonths}-month term · renews ${term.renewsLabel}",
                style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      );
    }

    final checkedIn = bookings.where((b) => b.attendanceStatus == "checked-in").toList();
    final used = sessionsUsedThisPeriod(info, plan, checkedIn);
    final max = effectiveMaxSessions(info, plan);
    final remaining = (max - used).clamp(0, max);
    final pct = max > 0 ? remaining / max : 0.0;
    final color = pct > 0.5 ? AppColors.grn : (pct > 0.2 ? AppColors.gold : AppColors.danger);

    return AppCard(
      borderColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.txt),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.kind == PlanKind.membership ? "MEMBERSHIP" : "PACKAGE",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "SESSIONS REMAINING",
            style: TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text("$remaining", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
              const SizedBox(width: 6),
              Text(
                "of $max ${plan.kind == PlanKind.membership ? "this month" : "in package"}",
                style: const TextStyle(fontSize: 13, color: AppColors.mute),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

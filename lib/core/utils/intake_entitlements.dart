import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";

/// Which intake forms a client has unlocked, and why.
///
/// The two questionnaires — Personalized Training Intake and Nutrition
/// Program Intake — are open to every client, whether they have bought
/// anything or not. They were previously gated behind a purchase, which had
/// it backwards: the answers are what a coach needs in order to sell the
/// right plan, and a client willing to fill them in before buying is the best
/// possible lead. Someone who finishes them with nothing purchased is sent
/// straight to the Access Hub, so the purchase follows the form rather than
/// blocking it.
///
/// What a purchase still decides is the coach-run physical assessment, which
/// is a session someone has to attend and conduct — not a form — and so only
/// exists when a membership or package pays for it.
class IntakeEntitlements {
  const IntakeEntitlements({
    required this.physical,
    required this.hasAnyPurchase,
  });

  /// The coach-conducted physical assessment (`physical`). Only ever unlocked
  /// by a membership or package — it's a session the client attends, not a
  /// form they fill in, so it has no meaning attached to a program purchase.
  final bool physical;

  /// False only when the client owns nothing at all, which is what drives
  /// both the "choose a plan to get started" card and the hand-off to the
  /// Access Hub once the questionnaires are done.
  final bool hasAnyPurchase;

  static const none = IntakeEntitlements(physical: false, hasAnyPurchase: false);

  /// Whether [assessmentKey] (as defined in data/intake_forms.dart) is
  /// unlocked. Unknown keys default to unlocked so that adding a form to the
  /// catalogue can never silently lock clients out of it.
  bool allows(String assessmentKey) => switch (assessmentKey) {
    // Open to everyone — see the note above.
    "personalTraining" => true,
    "nutritional" => true,
    "physical" => physical,
    _ => true,
  };
}

/// Everything this client currently holds: the primary membership/package
/// (`membershipPlanId`, which also drives billing and session counts) plus
/// every additional enrollment in `plans`. Both are read because a client can
/// hold a membership *and* one or more programs at the same time — the
/// primary slot alone can't express that.
IntakeEntitlements computeIntakeEntitlements({
  required ClientInfo info,
  required List<MembershipPlan> allPlans,
}) {
  final byId = {for (final p in allPlans) p.id: p};

  final held = <MembershipPlan>[
    if (info.membershipPlanId != null && byId[info.membershipPlanId] != null)
      byId[info.membershipPlanId]!,
    // Cancelled/expired enrollments must not keep an intake unlocked, so only
    // active ones count.
    for (final e in info.plans)
      if (e.status == "active" && byId[e.planId] != null) byId[e.planId]!,
  ];

  if (held.isEmpty) return IntakeEntitlements.none;

  // Only a membership or package pays for the coach-run assessment session.
  // A program of either kind grants programming, not gym time, so it can't.
  final physical = held.any((p) => p.kind == PlanKind.membership || p.kind == PlanKind.package);
  return IntakeEntitlements(physical: physical, hasAnyPurchase: true);
}

import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";

/// Which intake forms a client has unlocked, and why.
///
/// Intake forms are always *visible* — a client can see what the gym offers
/// before buying anything — but they only become fillable once a purchase
/// entitles them. The mapping, per spec:
///
///   Membership or Package → training + nutrition intake, and the coach-run
///                           physical assessment
///   Personalized Program  → training + nutrition intake
///   Nutrition Program     → nutrition intake only
///   Nothing purchased     → none; the client is pointed at Membership Hub
///
/// Entitlements are additive: someone holding a nutrition program who later
/// buys a personalized program ends up with both, which is exactly the case
/// the spec calls out ("if a client buys only a nutrition program, they will
/// also be allowed to buy a personalized program").
class IntakeEntitlements {
  const IntakeEntitlements({
    required this.training,
    required this.nutrition,
    required this.physical,
    required this.hasAnyPurchase,
  });

  /// "Personalized Training Intake" (assessment key `personalTraining`).
  final bool training;

  /// "Nutrition Program Intake" (assessment key `nutritional`).
  final bool nutrition;

  /// The coach-conducted physical assessment (`physical`). Only ever unlocked
  /// by a membership or package — it's a session the client attends, not a
  /// form they fill in, so it has no meaning attached to a program purchase.
  final bool physical;

  /// False only when the client owns nothing at all, which is what drives the
  /// "purchase something to get started" prompt rather than a per-form lock.
  final bool hasAnyPurchase;

  static const none = IntakeEntitlements(
    training: false, nutrition: false, physical: false, hasAnyPurchase: false,
  );

  /// Whether [assessmentKey] (as defined in data/intake_forms.dart) is
  /// unlocked. Unknown keys default to unlocked so that adding a form to the
  /// catalogue can never silently lock clients out of it.
  bool allows(String assessmentKey) => switch (assessmentKey) {
    "personalTraining" => training,
    "nutritional" => nutrition,
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

  var training = false;
  var nutrition = false;
  var physical = false;
  for (final p in held) {
    switch (p.kind) {
      case PlanKind.membership:
      case PlanKind.package:
        training = true;
        nutrition = true;
        physical = true;
      case PlanKind.program:
        training = true;
        nutrition = true;
      case PlanKind.nutritionProgram:
        nutrition = true;
    }
  }
  return IntakeEntitlements(
    training: training, nutrition: nutrition, physical: physical, hasAnyPurchase: true,
  );
}

/// Mirrors the shape produced by src/data/membershipPlans.js — trimmed to the
/// fields the client-facing screens actually read.
enum PlanKind { membership, package, program }

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.kind,
    this.maxSessions,
    this.termMonths,
    this.allowedTypes = const [],
    this.priceCents = 0,
    this.archived = false,
    this.paymentType,
  });

  final String id;
  final String name;
  final PlanKind kind;
  final int? maxSessions;
  final int? termMonths;
  final List<String> allowedTypes;

  /// Cents — "/mo" for membership plans, a flat one-time price for
  /// package/program plans. Drives Reports' revenue/payroll math.
  final int priceCents;
  final bool archived;

  /// "subscription" | "one-time" | null. Plans created before this field
  /// existed have neither — see [effectivePaymentType].
  final String? paymentType;
}

/// Mirrors membershipPlans.js `planPaymentType` — a plan with no explicit
/// paymentType defaults to "one-time" for a package, "subscription"
/// otherwise (memberships, and programs which are never sold directly).
String effectivePaymentType(MembershipPlan p) => p.paymentType ?? (p.kind == PlanKind.package ? "one-time" : "subscription");

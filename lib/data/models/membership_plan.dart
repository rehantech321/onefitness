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
}

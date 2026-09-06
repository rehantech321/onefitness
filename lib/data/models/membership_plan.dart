/// Mirrors the shape produced by src/data/membershipPlans.js — trimmed to the
/// fields the client-facing screens actually read.
///
/// [program] is the personalized *training* program; [nutritionProgram] is
/// the nutrition-only one. They're separate kinds rather than one "program"
/// bucket because they unlock different intake forms — see
/// intake_entitlements.dart — and a client can hold either, both, or neither.
enum PlanKind { membership, package, program, nutritionProgram }

/// What the client sees for each kind. "Program" alone was ambiguous once a
/// second program type existed.
String planKindLabel(PlanKind k) => switch (k) {
  PlanKind.membership => "Membership",
  PlanKind.package => "Package",
  PlanKind.program => "Personalized Program",
  PlanKind.nutritionProgram => "Nutrition Program",
};

/// Neither program kind is a membership or a session package — they grant
/// programming, not gym access or a session balance. Grouped here so the
/// several places that need "is this a program?" don't each re-list the
/// kinds and then get missed when another is added.
bool isProgramKind(PlanKind k) => k == PlanKind.program || k == PlanKind.nutritionProgram;

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
    this.feeItemProductId,
    this.category,
    this.allowGuests = false,
    this.guestFeeCents = 0,
    this.rolloverEnabled = false,
    this.rolloverMaxVisits = 0,
    this.cancellationNoticeDays = 0,
    this.earlyTerminationFeeCents = 0,
    this.serviceBalanceEnabled = false,
    this.sharingEnabled = false,
    this.sharingMaxAccounts = 1,
    this.public = true,
    this.limitOnePerAccount = false,
    this.expirationEnabled = false,
    this.expirationDays,
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

  /// A one-time package's linked Fee Item (Product id) — set via Package
  /// Setup's "Fee Item" picker. Referenced by ManageProducts.jsx's
  /// delete-guard: a product this points to gets archived, not deleted.
  final String? feeItemProductId;

  /// package_categories entry this plan is grouped under (Products/plan
  /// pickers share the same catalog — see packageCategoriesProvider).
  final String? category;

  // ── PackageSetupModal's Advanced Settings — highest-value subset ──
  // (contract attachment and a couple of lower-value toggles —
  // allowBookingBeyondBillingInterval, includeGuestsInVisitCount — are
  // deliberately not ported; see manage_memberships_screen.dart.)
  final bool allowGuests;

  /// One-time (package) plans only — subscriptions don't charge per-guest.
  final int guestFeeCents;

  /// Subscription (membership) plans only.
  final bool rolloverEnabled;
  final int rolloverMaxVisits;

  /// Subscription (membership) plans only — notice required before
  /// cancelling a renewal without incurring [earlyTerminationFeeCents].
  final int cancellationNoticeDays;
  final int earlyTerminationFeeCents;

  /// One-time (package) plans only.
  final bool serviceBalanceEnabled;

  final bool sharingEnabled;
  final int sharingMaxAccounts;
  final bool public;

  /// One-time (package) plans only.
  final bool limitOnePerAccount;
  final bool expirationEnabled;
  final int? expirationDays;
}

/// Mirrors membershipPlans.js `planPaymentType`, extended for programs.
///
/// Programs are always one-time, even if a plan row says otherwise: the
/// subscription slot on a client (`stripe_subscription_id`) belongs to their
/// membership, and cancel/change/freeze all operate on it. A recurring
/// program would either have to steal that slot — taking the membership's
/// billing controls with it — or bill forever with nothing in the app able to
/// stop it. Kept in sync with create-checkout-session, which enforces the
/// same rule server-side where the real charge is made.
String effectivePaymentType(MembershipPlan p) =>
    isProgramKind(p.kind) ? "one-time" : (p.paymentType ?? (p.kind == PlanKind.package ? "one-time" : "subscription"));

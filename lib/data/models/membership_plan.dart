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

/// Mirrors membershipPlans.js `planPaymentType` — a plan with no explicit
/// paymentType defaults to "one-time" for a package, "subscription"
/// otherwise (memberships, and programs which are never sold directly).
String effectivePaymentType(MembershipPlan p) => p.paymentType ?? (p.kind == PlanKind.package ? "one-time" : "subscription");

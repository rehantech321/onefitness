import "client_plan.dart";

/// Mirrors a roster entry (App.jsx `roster` items) — the client's account/
/// membership-facing record, as distinct from their day-to-day ClientRecord.
class ClientInfo {
  const ClientInfo({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.photo,
    this.city,
    this.birthday,
    this.membershipPlanId,
    this.plans = const [],
    this.membershipPaused = false,
    this.membershipPausedAt,
    this.membershipFreezeEndsAt,
    this.sessionCountOverride,
    this.sessionCountOverrideMonth,
    this.primaryTrainerId,
    this.hasOutstandingBalance = false,
    this.stripeSubscriptionId,
    this.pendingPlanId,
    this.pendingPlanEffectiveAt,
    this.membershipCancelsAt,
    this.redeemPointsNextRenewal = false,
    this.isStaff = false,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? photo;
  final String? city;
  final String? birthday;
  final String? membershipPlanId;
  final List<ClientPlanEnrollment> plans;
  final bool membershipPaused;
  final String? membershipPausedAt;
  final String? membershipFreezeEndsAt;
  final int? sessionCountOverride;

  /// "YYYY-MM" the override above was set in — for a recurring membership,
  /// scopes it to that one month (see effectiveMaxSessions); a package
  /// leaves this null and the override stays permanent.
  final String? sessionCountOverrideMonth;

  final String? primaryTrainerId;

  /// Non-null only when a real Stripe subscription backs the current plan —
  /// gates whether Change Plan (real proration/schedule) is even offered vs.
  /// falling back to a plain cancel-then-checkout.
  final String? stripeSubscriptionId;

  /// A "change at next renewal" request already scheduled via Stripe
  /// Subscription Schedule (change-membership-plan, timing:"end_of_cycle") —
  /// the plan it'll switch to, and the date that happens.
  final String? pendingPlanId;
  final String? pendingPlanEffectiveAt;

  /// Set once the client has confirmed Cancel (Membership Hub) — the real
  /// Stripe subscription is scheduled to end on this date (cancel_at_period_
  /// end:true, see cancel-membership) rather than ending immediately; access
  /// and booking eligibility both key off this date until then. Cleared
  /// server-side once Stripe actually finalizes the end (stripe-webhook).
  final String? membershipCancelsAt;

  /// "Redeem points automatically at my next purchase/renewal" flag — the
  /// non-Stripe-subscription redemption path (an active subscriber redeems
  /// immediately instead, see RewardsScreen). Applied and cleared server-side
  /// by create-checkout-session/stripe-webhook once that purchase completes.
  final bool redeemPointsNextRenewal;

  /// Drives the coach-side "payment" flag (highest-priority flag, blocks
  /// check-in) — mirrors roster.hasOutstandingBalance. No real billing
  /// integration exists yet, so this is only ever flipped by mock data.
  final bool hasOutstandingBalance;

  /// Set only on the synthetic ClientInfo a coach books themselves under
  /// via "Book session — Lead by example" (self_book_screen.dart) — never
  /// true for a real client/roster row. Bypasses every membership-access
  /// check in canBookOffering, same as canAccessService/withinBookingLimits
  /// on the web.
  final bool isStaff;

  ClientInfo copyWith({
    String? name,
    String? email,
    String? phone,
    String? photo,
    String? city,
    String? birthday,
    String? membershipPlanId,
    bool? membershipPaused,
    String? membershipPausedAt,
    String? membershipFreezeEndsAt,
    int? sessionCountOverride,
    String? sessionCountOverrideMonth,
    bool clearMembershipPausedAt = false,
    bool clearMembershipFreezeEndsAt = false,
    bool clearSessionCountOverride = false,
    bool? hasOutstandingBalance,
    bool clearMembershipPlanId = false,
    String? stripeSubscriptionId,
    bool clearStripeSubscriptionId = false,
    String? pendingPlanId,
    String? pendingPlanEffectiveAt,
    bool clearPendingPlan = false,
    String? membershipCancelsAt,
    bool clearMembershipCancelsAt = false,
    bool? redeemPointsNextRenewal,
  }) =>
      ClientInfo(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        photo: photo ?? this.photo,
        city: city ?? this.city,
        birthday: birthday ?? this.birthday,
        membershipPlanId: clearMembershipPlanId ? null : (membershipPlanId ?? this.membershipPlanId),
        plans: plans,
        membershipPaused: membershipPaused ?? this.membershipPaused,
        membershipPausedAt: clearMembershipPausedAt ? null : (membershipPausedAt ?? this.membershipPausedAt),
        membershipFreezeEndsAt: clearMembershipFreezeEndsAt ? null : (membershipFreezeEndsAt ?? this.membershipFreezeEndsAt),
        sessionCountOverride: clearSessionCountOverride ? null : (sessionCountOverride ?? this.sessionCountOverride),
        sessionCountOverrideMonth: clearSessionCountOverride ? null : (sessionCountOverrideMonth ?? this.sessionCountOverrideMonth),
        primaryTrainerId: primaryTrainerId,
        hasOutstandingBalance: hasOutstandingBalance ?? this.hasOutstandingBalance,
        stripeSubscriptionId: clearStripeSubscriptionId ? null : (stripeSubscriptionId ?? this.stripeSubscriptionId),
        pendingPlanId: clearPendingPlan ? null : (pendingPlanId ?? this.pendingPlanId),
        pendingPlanEffectiveAt: clearPendingPlan ? null : (pendingPlanEffectiveAt ?? this.pendingPlanEffectiveAt),
        membershipCancelsAt: clearMembershipCancelsAt ? null : (membershipCancelsAt ?? this.membershipCancelsAt),
        redeemPointsNextRenewal: redeemPointsNextRenewal ?? this.redeemPointsNextRenewal,
        isStaff: isStaff,
      );
}

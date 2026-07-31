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
    this.primaryTrainerId,
    this.hasOutstandingBalance = false,
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
  final String? primaryTrainerId;

  /// Drives the coach-side "payment" flag (highest-priority flag, blocks
  /// check-in) — mirrors roster.hasOutstandingBalance. No real billing
  /// integration exists yet, so this is only ever flipped by mock data.
  final bool hasOutstandingBalance;

  ClientInfo copyWith({
    String? name,
    String? email,
    String? phone,
    String? city,
    bool? membershipPaused,
    String? membershipPausedAt,
    String? membershipFreezeEndsAt,
    int? sessionCountOverride,
    bool clearMembershipPausedAt = false,
    bool clearMembershipFreezeEndsAt = false,
    bool clearSessionCountOverride = false,
    bool? hasOutstandingBalance,
  }) =>
      ClientInfo(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        photo: photo,
        city: city ?? this.city,
        birthday: birthday,
        membershipPlanId: membershipPlanId,
        plans: plans,
        membershipPaused: membershipPaused ?? this.membershipPaused,
        membershipPausedAt: clearMembershipPausedAt ? null : (membershipPausedAt ?? this.membershipPausedAt),
        membershipFreezeEndsAt: clearMembershipFreezeEndsAt ? null : (membershipFreezeEndsAt ?? this.membershipFreezeEndsAt),
        sessionCountOverride: clearSessionCountOverride ? null : (sessionCountOverride ?? this.sessionCountOverride),
        primaryTrainerId: primaryTrainerId,
        hasOutstandingBalance: hasOutstandingBalance ?? this.hasOutstandingBalance,
      );
}

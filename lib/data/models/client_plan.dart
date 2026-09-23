/// Mirrors the web `ClientPlanEnrollment` shape — one entry in `clients.plans`.
class ClientPlanEnrollment {
  const ClientPlanEnrollment({
    required this.planId,
    required this.status,
    required this.startDate,
    this.termMonths,
    this.subscriptionId,
    this.cancelsAt,
    this.rolloverSessions = 0,
    this.rolloverMonth,
    this.endsAt,
  });

  final String planId;
  final String status; // active | cancelled | ...
  final String startDate; // ISO yyyy-MM-dd
  final int? termMonths;

  /// The Stripe subscription this plan renews on — set for a paid
  /// membership, so each one a client holds renews and cancels on its own.
  final String? subscriptionId;

  /// Set once the client cancels a paid plan: it stays usable until this
  /// date (what's already paid for), then ends.
  final String? cancelsAt;

  /// Sessions carried over from the previous month, under the plan's
  /// roll-over rule (Plans → Advanced → roll over). They're added to this
  /// month's allowance and expire with it.
  final int rolloverSessions;

  /// The "YYYY-MM" [rolloverSessions] belongs to — a carry-over is good for
  /// that one month only, never stacked month after month.
  final String? rolloverMonth;

  /// Set when the client switched to a different plan: the old plan's
  /// remaining sessions stay usable until this date, but it doesn't renew.
  final String? endsAt;

  ClientPlanEnrollment copyWith({
    String? status,
    String? cancelsAt,
    bool clearCancelsAt = false,
    int? rolloverSessions,
    String? rolloverMonth,
    String? endsAt,
  }) =>
      ClientPlanEnrollment(
        planId: planId,
        status: status ?? this.status,
        startDate: startDate,
        termMonths: termMonths,
        subscriptionId: subscriptionId,
        cancelsAt: clearCancelsAt ? null : (cancelsAt ?? this.cancelsAt),
        rolloverSessions: rolloverSessions ?? this.rolloverSessions,
        rolloverMonth: rolloverMonth ?? this.rolloverMonth,
        endsAt: endsAt ?? this.endsAt,
      );
}

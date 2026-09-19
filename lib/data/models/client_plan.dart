/// Mirrors the web `ClientPlanEnrollment` shape — one entry in `clients.plans`.
class ClientPlanEnrollment {
  const ClientPlanEnrollment({
    required this.planId,
    required this.status,
    required this.startDate,
    this.termMonths,
    this.subscriptionId,
    this.cancelsAt,
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

  ClientPlanEnrollment copyWith({String? status, String? cancelsAt, bool clearCancelsAt = false}) => ClientPlanEnrollment(
        planId: planId,
        status: status ?? this.status,
        startDate: startDate,
        termMonths: termMonths,
        subscriptionId: subscriptionId,
        cancelsAt: clearCancelsAt ? null : (cancelsAt ?? this.cancelsAt),
      );
}

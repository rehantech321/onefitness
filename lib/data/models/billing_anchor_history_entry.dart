/// Billing Cycle Anchor Date spec §4 — one row of a client's billing-anchor
/// change history, for support/dispute purposes. Read-only from the app's
/// perspective; every row is written by change-billing-anchor (service
/// role) at the moment an owner applies a change.
class BillingAnchorHistoryEntry {
  const BillingAnchorHistoryEntry({
    required this.id,
    required this.oldValue,
    required this.newValue,
    required this.changedAt,
    this.changedByName,
    this.proratedAmountCents,
    this.nextChargeDate,
  });

  final String id;
  final int? oldValue;
  final int newValue;
  final String changedAt;
  final String? changedByName;

  /// Null when the client had no active Stripe subscription at the time —
  /// nothing was prorated, only the field itself changed.
  final int? proratedAmountCents;
  final String? nextChargeDate;
}

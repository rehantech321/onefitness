/// Owner-managed coupon-code catalog — reusable named discount codes
/// applicable at checkout (Membership Hub self-checkout, and the
/// coach/owner "Purchase for Client" checkout link). Mirrors the
/// [Product]/[WaiverDoc] catalog convention (single JSONB row per code).
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    this.type = "percent",
    this.percentOff = 0,
    this.flatOffCents = 0,
    this.archived = false,
  });

  final String id;

  /// Display/entry key — what a buyer types in, and what shows in the
  /// coach's coupon dropdown. Stored upper-cased for case-insensitive entry.
  final String code;

  /// "percent" | "flat".
  final String type;

  /// 1-100, used when [type] is "percent".
  final int percentOff;

  /// Cents, used when [type] is "flat".
  final int flatOffCents;
  final bool archived;

  String get valueLabel => type == "flat" ? "\$${(flatOffCents / 100).toStringAsFixed(2)} off" : "$percentOff% off";
}

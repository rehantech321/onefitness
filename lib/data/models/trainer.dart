import "availability_block.dart";

/// Mirrors a trainer/coach record (App.jsx `trainers`) — trimmed to the
/// fields the client-facing Chat and Booking screens need.
class Trainer {
  const Trainer({
    required this.id,
    required this.name,
    this.photo,
    this.phone,
    this.email,
    this.locationName,
    this.locationAddress,
    this.availability = const [],
    this.commissionRate = 0,
  });

  final String id;
  final String name;
  final String? photo;
  final String? phone;
  final String? email;
  final String? locationName;
  final String? locationAddress;
  final List<AvailabilityBlock> availability;

  /// Percent (e.g. 20 = 20%) of session revenue paid to this coach — feeds
  /// Reports → Payroll/Commissions and the coach's own My Pay screen.
  final num commissionRate;
}

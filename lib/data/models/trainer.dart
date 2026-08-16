import "availability_block.dart";

/// A single entry in a trainer's `locations` jsonb list (real schema —
/// see supabaseData.js `trainerRowToApp`/`trainerFieldsToRow`).
class TrainerLocation {
  const TrainerLocation({required this.name, this.address});

  final String name;
  final String? address;
}

/// One before/after transformation-photo pair, as stored in the trainer's
/// `before_afters` jsonb column. Either side may be null/empty.
class TrainerBeforeAfter {
  const TrainerBeforeAfter({required this.id, this.left, this.right});

  final String id;
  final String? left;
  final String? right;
}

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
    this.locations = const [],
    this.bio,
    this.beforeAfters = const [],
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

  /// Full `locations` list (the real schema supports more than one; the
  /// app's own edit form only ever writes a single entry, but a coach's
  /// row may carry more if edited elsewhere).
  final List<TrainerLocation> locations;

  final String? bio;
  final List<TrainerBeforeAfter> beforeAfters;
  final List<AvailabilityBlock> availability;

  /// Percent (e.g. 20 = 20%) of session revenue paid to this coach — feeds
  /// Reports → Payroll/Commissions and the coach's own My Pay screen.
  final num commissionRate;
}

import "availability_block.dart";

/// A single entry in a trainer's `locations` jsonb list (real schema —
/// see supabaseData.js `trainerRowToApp`/`trainerFieldsToRow`).
class TrainerLocation {
  const TrainerLocation({required this.id, required this.name, this.address, this.hint});

  final String id;
  final String name;
  final String? address;
  final String? hint;
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
    this.disciplines = const [],
    this.sessionTypes = const [],
  });

  final String id;
  final String name;
  final String? photo;
  final String? phone;
  final String? email;
  final String? locationName;
  final String? locationAddress;

  /// Real, directly-stored columns — NOT derived from [availability]'s
  /// blocks (mirrors `trainerDisciplines`/`trainerSessionTypes` in
  /// schedulingHelpers.js, which read `t.disciplines`/`t.sessionTypes`
  /// directly). A coach can select a discipline/session type before ever
  /// adding an availability block for it.
  final List<String> disciplines;
  final List<String> sessionTypes;

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

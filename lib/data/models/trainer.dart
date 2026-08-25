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

/// A block of time this coach won't be working — a single day
/// (startDate == endDate) or a range, with an optional note. Stored on the
/// trainer's `unavailability` jsonb column. Doesn't affect existing
/// bookings inside the window (Coach Availability Tab spec, deliberate
/// scope boundary) — only blocks NEW ones from being made, see
/// booking_utils.dart's `fallsInUnavailability`.
class TrainerUnavailability {
  const TrainerUnavailability({required this.id, required this.startDate, required this.endDate, this.note});

  final String id;
  final String startDate; // ISO yyyy-MM-dd
  final String endDate; // ISO yyyy-MM-dd — same as startDate for a single day
  final String? note;
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
    this.reviewedByOwner = true,
    this.signupAt,
    this.payoutMode = "perSession",
    this.payoutRateCents = 0,
    this.referralCommissionPercent = 0,
    this.coachCode,
    this.unavailability = const [],
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

  /// Time off — see [TrainerUnavailability]. Distinct from [availability]'s
  /// weekly recurring blocks: this is calendar-date-specific, blocks new
  /// bookings only (never touches existing ones), and is checked separately
  /// at slot-generation time (booking_utils.dart's fallsInUnavailability).
  final List<TrainerUnavailability> unavailability;

  /// Percent (e.g. 20 = 20%) of session revenue paid to this coach — legacy
  /// field, no longer read by payroll math (see [payoutMode]/
  /// [payoutRateCents]). Left in the model/DB rather than removed since
  /// dropping a column is destructive and this app never reads it anymore.
  final num commissionRate;

  /// False only for a coach who self-signed-up with an approval code and
  /// hasn't yet been opened by the owner on Coaches Overview (mirrors
  /// CoachesOverview.jsx's "New" badge / `reviewedByOwner === false`).
  /// Owner-added coaches (Staff → +Trainer) start `true` — no review needed.
  final bool reviewedByOwner;

  /// ISO date the coach self-signed-up, if they did (null for owner-added
  /// coaches) — shown in the expanded Coaches Overview card.
  final String? signupAt;

  /// "perClient" | "perHour" | "perSession" — owner picks exactly one mode
  /// per coach; [payoutRateCents] is that mode's $ rate (cents). Replaces
  /// [commissionRate] as the real payroll source of truth — see
  /// report_utils.dart's TrainerRangeStats.
  final String payoutMode;
  final int payoutRateCents;

  /// Percent of every membership/package purchase made by a client this
  /// coach referred (via [coachCode]) — charged to the client as a
  /// surcharge on top of the listed price, credited to this coach as a
  /// `charges` row (category "referral_commission"). Independent of
  /// [payoutMode]/[payoutRateCents] — a second, separate income stream.
  final num referralCommissionPercent;

  /// Unique, set once at signup (self-signup or owner-added), never
  /// editable afterward — a client entering this at their own signup links
  /// to this coach (see clients.referred_by_trainer_id) and becomes their
  /// primary client. Null for a coach created before this feature shipped.
  final String? coachCode;
}

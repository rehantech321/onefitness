/// Mirrors a booking record in App.jsx `bookings`.
class Booking {
  const Booking({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.date, // ISO yyyy-MM-dd
    required this.slot, // minutes from midnight
    required this.sessionType,
    required this.discipline,
    this.status = "confirmed",
    this.attendanceStatus,
    this.clientStartedAt,
    this.locationName,
    this.isPhysicalAssessment = false,
    this.overriddenBy,
    this.overriddenAt,
    this.overrideReason,
    this.planId,
    this.durationMin = 60,
  });

  final String id;
  final String clientId;
  final String trainerId;
  final String date;
  final int slot;
  final String sessionType;
  final String discipline;
  final String status;
  final String? attendanceStatus; // checked-in | no-show | ...

  /// Set only when the CLIENT started this session themselves, early, from
  /// their own dashboard.
  ///
  /// Deliberately separate from [attendanceStatus]: a coach marking someone
  /// present writes "checked-in" too, and keying anything on that made an
  /// ordinary attendance tick at 6pm unlock starting a 9pm session. Nothing
  /// a coach does sets this.
  final String? clientStartedAt;

  bool get clientStartedEarly => clientStartedAt != null;
  final String? locationName;
  final bool isPhysicalAssessment;

  /// Set only when an owner pushed a manual booking past a real conflict or
  /// capacity block (AddManualBookingModal.jsx's override confirmation) —
  /// `overrideReason` is "conflict" | "capacity".
  final String? overriddenBy;
  final String? overriddenAt;
  final String? overrideReason;

  /// The held plan whose session this booking used — chosen by
  /// canBookOffering at booking time. A client can hold a membership and
  /// several packages together, so usage is attributed per plan rather than
  /// inferred from the session type. Null for rows made before this existed.
  final String? planId;

  /// Minutes the session runs. 60 unless staff set an end time when booking.
  final int durationMin;

  int get endSlot => slot + durationMin;

  Booking copyWith({String? attendanceStatus}) => Booking(
        id: id,
        clientId: clientId,
        trainerId: trainerId,
        date: date,
        slot: slot,
        sessionType: sessionType,
        discipline: discipline,
        status: status,
        attendanceStatus: attendanceStatus,
        clientStartedAt: clientStartedAt,
        locationName: locationName,
        isPhysicalAssessment: isPhysicalAssessment,
        overriddenBy: overriddenBy,
        overriddenAt: overriddenAt,
        overrideReason: overrideReason,
        planId: planId,
        durationMin: durationMin,
      );
}

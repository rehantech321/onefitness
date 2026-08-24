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
    this.locationName,
    this.isPhysicalAssessment = false,
    this.overriddenBy,
    this.overriddenAt,
    this.overrideReason,
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
  final String? locationName;
  final bool isPhysicalAssessment;

  /// Set only when an owner pushed a manual booking past a real conflict or
  /// capacity block (AddManualBookingModal.jsx's override confirmation) —
  /// `overrideReason` is "conflict" | "capacity".
  final String? overriddenBy;
  final String? overriddenAt;
  final String? overrideReason;

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
        locationName: locationName,
        isPhysicalAssessment: isPhysicalAssessment,
        overriddenBy: overriddenBy,
        overriddenAt: overriddenAt,
        overrideReason: overrideReason,
      );
}

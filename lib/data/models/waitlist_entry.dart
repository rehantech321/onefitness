/// Mirrors a row in the `waitlist` table (App.jsx `waitlist`) — two status
/// values in one table: "waiting" (single-slot, join-a-full-session) and
/// "pending-approval" (Advanced Booking recurring-series requests, needs
/// the owner's approval before becoming a real booking).
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.trainerId,
    required this.trainerName,
    required this.date,
    required this.slot,
    required this.sessionType,
    this.discipline,
    required this.status, // "waiting" | "pending-approval"
    this.position,
    this.addedAt,
    this.requestedAt,
    this.seriesId,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String trainerId;
  final String trainerName;
  final String date; // ISO yyyy-MM-dd
  final int slot;
  final String sessionType;
  final String? discipline;
  final String status;
  final int? position;
  final String? addedAt;
  final String? requestedAt;
  final String? seriesId;
}

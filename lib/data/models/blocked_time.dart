/// Mirrors one entry in the coach's blocked-time-off calendar.
class BlockedTime {
  const BlockedTime({
    required this.id,
    required this.trainerId,
    required this.date, // ISO yyyy-MM-dd
    this.allDay = true,
    this.startMin,
    this.endMin,
    this.reason,
  });

  final String id;
  final String trainerId;
  final String date;
  final bool allDay;
  final int? startMin;
  final int? endMin;
  final String? reason;
}

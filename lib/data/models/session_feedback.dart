/// Mirrors one entry in `client.sessionFeedback`.
class SessionFeedbackEntry {
  const SessionFeedbackEntry({
    required this.id,
    required this.rating, // 1-5
    this.note,
    required this.coachName,
    required this.loggedAt,
  });

  final String id;
  final int rating;
  final String? note;
  final String coachName;
  final String loggedAt;
}

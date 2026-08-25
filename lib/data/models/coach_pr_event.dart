/// One coach-verified client PR — logged via the "Log PR" action alongside
/// (not instead of) the existing client-facing `record_breaker` merit
/// badge grant. Kept as its own append-only log (unlike `merit_badges`,
/// which only keeps one active `record_breaker` row per client) so PR
/// Factory can count every verified PR event a coach logs this month, even
/// for a client who already has an active record_breaker badge from a
/// prior month.
class CoachPrEvent {
  const CoachPrEvent({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.exerciseName,
    required this.earnedAt,
    this.note,
  });

  final String id;
  final String clientId;
  final String trainerId;
  final String exerciseName;
  final String earnedAt; // ISO timestamp
  final String? note;
}

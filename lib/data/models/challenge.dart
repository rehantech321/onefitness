/// One manual progress entry a client logs against a challenge (e.g. a new
/// heaviest lift, or a weigh-in) — mirrors challengeHelpers.js's
/// `client.challengeProgress[challengeId]` entries.
class ChallengeProgressEntry {
  const ChallengeProgressEntry({required this.value, required this.loggedAt});
  final double value;
  final String loggedAt;
}

/// A named competitor's precomputed score, for leaderboard flavor without
/// modeling every other client's full record.
class LeaderboardEntry {
  const LeaderboardEntry({required this.clientId, required this.name, required this.score});
  final String clientId;
  final String name;
  final double score;
}

/// Mirrors a challenge record (App.jsx `challenges`) — trimmed to the
/// client-facing fields.
class Challenge {
  const Challenge({
    required this.id,
    required this.name,
    required this.template,
    required this.metric,
    required this.startDate,
    required this.endDate,
    this.description,
    this.prize,
    this.participantIds = const [],
    this.otherLeaderboard = const [],
    this.winnerClientId,
  });

  final String id;
  final String name;
  final String template; // key into kChallengeTemplates
  final String metric;
  final String startDate;
  final String endDate;
  final String? description;
  final String? prize;
  final List<String> participantIds;
  final List<LeaderboardEntry> otherLeaderboard;
  final String? winnerClientId;

  Challenge copyWith({List<String>? participantIds}) => Challenge(
        id: id,
        name: name,
        template: template,
        metric: metric,
        startDate: startDate,
        endDate: endDate,
        description: description,
        prize: prize,
        participantIds: participantIds ?? this.participantIds,
        otherLeaderboard: otherLeaderboard,
        winnerClientId: winnerClientId,
      );
}

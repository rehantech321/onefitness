/// One manual progress entry a client logs against a challenge (e.g. a new
/// heaviest lift, or a weigh-in) — mirrors challengeHelpers.js's
/// `client.challengeProgress[challengeId]` entries.
class ChallengeProgressEntry {
  const ChallengeProgressEntry({required this.value, required this.loggedAt});
  final double value;
  final String loggedAt;
}

/// A badge awarded for a challenge — either the actual winner's badge
/// (`challengeId` == the challenge's own id) or the participation badge
/// every registered client gets when a coach awards badges
/// (`challengeId` == `"complete-{challengeId}"`) — mirrors
/// `client.challengeBadges` (CoachChallengeDetail.jsx `awardBadges`).
class ChallengeBadge {
  const ChallengeBadge({required this.challengeId, required this.name, required this.awardedAt});
  final String challengeId;
  final String name;
  final String awardedAt;
}

/// A named competitor's precomputed score, for leaderboard flavor without
/// modeling every other client's full record.
class LeaderboardEntry {
  const LeaderboardEntry({required this.clientId, required this.name, required this.score});
  final String clientId;
  final String name;
  final double score;
}

/// A challenge type the gym defined itself, offered in the "choose a type"
/// list alongside the eight built into the app.
///
/// A custom type chooses an existing scorer rather than defining one: every
/// leaderboard comes from `calcChallengeScore`, which only knows the engines
/// it has branches for, so a type that invented its own scoring would rank
/// every participant at zero. [basis] names the engine; everything else is
/// presentation.
class ChallengeTemplate {
  const ChallengeTemplate({
    required this.key,
    required this.emoji,
    required this.label,
    required this.metric,
    required this.description,
    required this.basis,
    this.trainerId,
  });

  final String key;
  final String emoji;
  final String label;

  /// What the leaderboard number means, in the gym's own words ("Steps
  /// logged"). Wording only — [basis] is what actually produces the number.
  final String metric;

  final String description;

  /// Which built-in scorer ranks this type. One of [kScoringBases].
  final String basis;

  /// Null for a gym-wide type every coach can build from; a coach id for one
  /// only that coach sees. Same scoping rule as `Challenge.trainerId`.
  final String? trainerId;
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
    this.winnerMode = "auto",
    this.rewardPoints,
    this.rewardProductId,
    this.trainerId,
    this.emoji,
    this.scoringBasis,
  });

  /// Rewards points offered to the winner (1, 2, 3 or 5), on top of any
  /// free-text [prize]. Granted through the points ledger when the winner
  /// is set.
  final int? rewardPoints;

  /// A shop product offered to the winner. Recorded on the challenge and
  /// shown to clients; handing it over is the gym's job.
  final String? rewardProductId;

  /// Scopes the challenge to one coach's clients. Null means everyone.
  final String? trainerId;

  /// The icon, copied from the type when this challenge was created rather
  /// than looked up through it. A gym-defined type can be deleted; a
  /// challenge built from one — especially a finished one, whose leaderboard
  /// is a record of what happened — must keep rendering and ranking exactly
  /// as it did. Null means a built-in type, which supplies its own.
  final String? emoji;

  /// Which scorer ranks this challenge, for one built from a gym-defined
  /// type. Null for the eight built-in types, which score from [template] as
  /// they always have. Copied at creation for the same reason as [emoji].
  final String? scoringBasis;

  final String id;
  final String name;

  /// For a built-in challenge, a key into `kChallengeTemplates`. For one
  /// built from a gym-defined type, that type's key — which is why nothing
  /// may assume this resolves to a built-in.
  final String template;

  final String metric;
  final String startDate;
  final String endDate;
  final String? description;
  final String? prize;
  final List<String> participantIds;
  final List<LeaderboardEntry> otherLeaderboard;
  final String? winnerClientId;
  final String winnerMode; // "auto" | "coach"

  Challenge copyWith({List<String>? participantIds, String? winnerClientId}) => Challenge(
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
        winnerClientId: winnerClientId ?? this.winnerClientId,
        winnerMode: winnerMode,
        rewardPoints: rewardPoints,
        rewardProductId: rewardProductId,
        trainerId: trainerId,
        emoji: emoji,
        scoringBasis: scoringBasis,
      );
}

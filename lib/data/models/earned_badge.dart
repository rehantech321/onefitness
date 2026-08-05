/// Mirrors one row in `merit_badges` — a client's earned (and possibly
/// later revoked) Merit Badge.
class EarnedBadge {
  const EarnedBadge({
    required this.id,
    required this.clientId,
    required this.badgeKey,
    required this.earnedAt, // ISO date
    this.earnedMethod = "automatic", // "automatic" | "coach"
    this.grantedByUserId,
    this.note,
    this.revokedAt,
    this.revokedByUserId,
  });

  final String id;
  final String clientId;
  final String badgeKey;
  final String earnedAt;
  final String earnedMethod;
  final String? grantedByUserId;
  final String? note;
  final String? revokedAt;
  final String? revokedByUserId;

  bool get isActive => revokedAt == null;

  EarnedBadge copyWith({String? revokedAt, String? revokedByUserId}) => EarnedBadge(
        id: id,
        clientId: clientId,
        badgeKey: badgeKey,
        earnedAt: earnedAt,
        earnedMethod: earnedMethod,
        grantedByUserId: grantedByUserId,
        note: note,
        revokedAt: revokedAt ?? this.revokedAt,
        revokedByUserId: revokedByUserId ?? this.revokedByUserId,
      );
}

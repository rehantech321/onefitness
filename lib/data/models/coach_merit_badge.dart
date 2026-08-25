/// One earned Coach Merit Badge — Coach Merit Badge System (monthly
/// coaching-performance incentives, distinct from the client-facing
/// merit_badges table). One row per (trainer, badge, month) — see
/// coach_merit_badge_utils.dart for the 7 badge keys and their attainment
/// logic, and SupabaseService.finalizeCoachBadgesForMonth for how rows here
/// get created.
class CoachMeritBadge {
  const CoachMeritBadge({
    required this.id,
    required this.trainerId,
    required this.badgeKey,
    required this.periodMonth,
    required this.earnedAt,
    required this.rewardCents,
    this.payoutStatus = "pending",
    this.note,
  });

  final String id;
  final String trainerId;
  final String badgeKey;

  /// "YYYY-MM" — the calendar month this badge was earned for, not when the
  /// row was inserted (finalization can lag behind month-end).
  final String periodMonth;
  final String earnedAt; // ISO timestamp

  /// Snapshotted from the owner's configured value at the moment this badge
  /// was earned — never rewritten if the owner later changes the setting.
  final int rewardCents;
  final String payoutStatus; // pending | paid
  final String? note;
}

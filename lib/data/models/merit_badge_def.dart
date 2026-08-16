/// Mirrors src/constants/meritBadges.js `MERIT_BADGES` — static display
/// metadata for the badge catalog. Real eligibility/award logic is
/// Supabase-edge-function-only in the source (award-merit-badge,
/// grant-merit-badge) and isn't ported here; badges in this mock build are
/// only ever seeded or coach-awarded, never automatically computed.
class MeritBadgeDef {
  const MeritBadgeDef({required this.key, required this.name, required this.category, required this.description});

  final String key;
  final String name;
  final String category; // "automatic" | "coach"
  final String description;
}

const kMeritBadges = <MeritBadgeDef>[
  MeritBadgeDef(
    key: "one_fitness",
    name: "ONE Fitness",
    category: "automatic",
    description: "Awarded immediately after purchasing any ONE Fitness membership or package — every active member's base badge. Removed if the client no longer has an active membership or package.",
  ),
  MeritBadgeDef(
    key: "early_bird",
    name: "Early Bird",
    category: "automatic",
    description: "Awarded after completing an entire month of membership using only sessions before 9:00 AM. Removed if the following month doesn't also meet this.",
  ),
  MeritBadgeDef(
    key: "daytimer",
    name: "Daytimer",
    category: "automatic",
    description: "Awarded after completing an entire month of membership using only sessions between 9:00 AM and 6:00 PM. Removed if the following month doesn't also meet this.",
  ),
  MeritBadgeDef(
    key: "night_owl",
    name: "Night Owl",
    category: "automatic",
    description: "Awarded after completing an entire month of membership using only sessions after 6:00 PM. Removed if the following month doesn't also meet this.",
  ),
  MeritBadgeDef(
    key: "progress_tracker",
    name: "Progress Tracker",
    category: "automatic",
    description: "Three consecutive weeks of consistent client-logged progress (photos, measurements, or workouts logged from the client's own account). Re-evaluated every 3 weeks.",
  ),
  MeritBadgeDef(
    key: "record_breaker",
    name: "PR",
    category: "coach",
    description: "Awarded by a coach when a client achieves a Personal Record. Does not expire automatically; stays until a coach removes it.",
  ),
  MeritBadgeDef(
    key: "community_builder",
    name: "Community Builder",
    category: "automatic",
    description: "Awarded to a client who successfully refers a new member. Stays active for 6 months from the most recent successful referral.",
  ),
  MeritBadgeDef(
    key: "squad",
    name: "Squad",
    category: "automatic",
    description: "Active as long as the client belongs to any ONE Fitness Squad. Removed if they leave.",
  ),
  MeritBadgeDef(
    key: "champion",
    name: "Champion",
    category: "automatic",
    description: "Won an official ONE Fitness Challenge. Permanent — never expires.",
  ),
  MeritBadgeDef(
    key: "habit",
    name: "Habit",
    category: "automatic",
    description: "Three consecutive weeks of consistent client-entered habit tracking. Re-evaluated every 3 weeks.",
  ),
  MeritBadgeDef(
    key: "gym_citizen",
    name: "Gym Citizen",
    category: "coach",
    description: "Awarded to clients who consistently demonstrate outstanding gym etiquette, come prepared, respect the facility, and positively contribute to the One Fitness community.",
  ),
];

MeritBadgeDef? meritBadgeByKey(String key) {
  for (final b in kMeritBadges) {
    if (b.key == key) return b;
  }
  return null;
}

/// Mirrors constants/meritBadges.js `MERIT_BADGE_MIN_ACTIVE_FOR_POINTS`/
/// `MERIT_BADGE_BONUS_POINTS` — fewer than the minimum active (non-revoked)
/// badges earns 0 bonus points; at or above it, a flat bonus (not
/// per-badge, and not additional for more badges beyond the minimum).
/// Gym Citizen's 10 coach-checked sub-badges (gym_citizen_rerack, ...)
/// never count toward this — they aren't in [kMeritBadges] at all, so
/// filtering an earned-badge-key set against that catalog already excludes
/// them, same as MeritBadgeRow's own display filtering.
const kMeritBadgeMinActiveForPoints = 5;
const kMeritBadgeBonusPoints = 5;

/// Keyed by MeritBadgeDef.key — mirrors src/constants/badgeAssets.js.
const kBadgeImagePaths = {
  "one_fitness": "assets/images/badges/one_fitness.png",
  "early_bird": "assets/images/badges/early_bird.png",
  "daytimer": "assets/images/badges/daytimer.png",
  "night_owl": "assets/images/badges/night_owl.png",
  "progress_tracker": "assets/images/badges/progress_tracker.png",
  "record_breaker": "assets/images/badges/record_breaker.png",
  "community_builder": "assets/images/badges/community_builder.png",
  "squad": "assets/images/badges/squad.png",
  "champion": "assets/images/badges/champion.png",
  "habit": "assets/images/badges/habit.png",
  "gym_citizen": "assets/images/badges/gym_citizen.png",
};

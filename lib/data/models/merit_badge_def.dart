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

class SubBadgeDef {
  const SubBadgeDef({required this.key, required this.name, required this.description});
  final String key;
  final String name;
  final String description;
}

/// Gym Citizen's 10 coach-verified sub-badges — deliberately NOT part of
/// [kMeritBadges] (see that constant's own doc comment for why). Checked
/// off one at a time by a coach; once all 10 are active, the parent
/// "gym_citizen" badge is awarded automatically server-side.
const kGymCitizenSubBadges = <SubBadgeDef>[
  SubBadgeDef(key: "gym_citizen_rerack", name: "Re-Rack", description: "Returns weights and equipment to their proper locations."),
  SubBadgeDef(key: "gym_citizen_setup", name: "Setup", description: "Can properly set up the equipment needed for their workout."),
  SubBadgeDef(key: "gym_citizen_reset", name: "Reset", description: "Resets and clears their training station after use."),
  SubBadgeDef(key: "gym_citizen_loadup", name: "Load Up", description: "Participates in loading and unloading their own weights."),
  SubBadgeDef(key: "gym_citizen_knowit", name: "Know It", description: "Knows how to follow their personalized workout/program in the app."),
  SubBadgeDef(key: "gym_citizen_countreps", name: "Count Reps", description: "Takes responsibility for counting their own repetitions."),
  SubBadgeDef(key: "gym_citizen_coachable", name: "Coachable", description: "Listens to coaching cues and applies corrections."),
  SubBadgeDef(key: "gym_citizen_gymaware", name: "Gym Aware", description: "Demonstrates awareness of other clients, coaches, equipment, and surroundings."),
  SubBadgeDef(key: "gym_citizen_workoutready", name: "Workout Ready", description: "Arrives prepared and can transition through their workout without requiring the coach to manage every step."),
  SubBadgeDef(key: "gym_citizen_gymcourtesy", name: "Gym Courtesy", description: "Demonstrates courtesy and respect toward coaches, clients, equipment, and the ONE Fitness environment."),
];
final kGymCitizenSubBadgeKeys = kGymCitizenSubBadges.map((b) => b.key).toSet();

/// Progress Tracker's 3 sub-badges — earned automatically (no coach
/// action), one per action logged within the last 6 months. Same
/// "kept out of kMeritBadges" reasoning as Gym Citizen's.
const kProgressTrackerSubBadges = <SubBadgeDef>[
  SubBadgeDef(key: "progress_tracker_photo", name: "Progress Photo", description: "Log a progress photo."),
  SubBadgeDef(key: "progress_tracker_measurements", name: "Measurements", description: "Log a body measurement."),
  SubBadgeDef(key: "progress_tracker_workout", name: "Log Workout", description: "Log a workout from your own program."),
];
final kProgressTrackerSubBadgeKeys = kProgressTrackerSubBadges.map((b) => b.key).toSet();

/// Keyed by SubBadgeDef.key — mirrors src/constants/badgeAssets.js `SUB_BADGE_IMAGES`.
const kSubBadgeImagePaths = {
  "gym_citizen_rerack": "assets/images/badges/gym_citizen_rerack.jpeg",
  "gym_citizen_setup": "assets/images/badges/gym_citizen_setup.jpeg",
  "gym_citizen_reset": "assets/images/badges/gym_citizen_reset.jpeg",
  "gym_citizen_loadup": "assets/images/badges/gym_citizen_loadup.jpeg",
  "gym_citizen_knowit": "assets/images/badges/gym_citizen_knowit.jpeg",
  "gym_citizen_countreps": "assets/images/badges/gym_citizen_countreps.jpeg",
  "gym_citizen_coachable": "assets/images/badges/gym_citizen_coachable.jpeg",
  "gym_citizen_gymaware": "assets/images/badges/gym_citizen_gymaware.jpeg",
  "gym_citizen_workoutready": "assets/images/badges/gym_citizen_workoutready.jpeg",
  "gym_citizen_gymcourtesy": "assets/images/badges/gym_citizen_gymcourtesy.jpeg",
  "progress_tracker_photo": "assets/images/badges/progress_tracker_photo.png",
  "progress_tracker_measurements": "assets/images/badges/progress_tracker_measurements.png",
  "progress_tracker_workout": "assets/images/badges/progress_tracker_workout.png",
};

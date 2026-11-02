/// The coach-conducted Physical Assessment — a movement screen, not a
/// questionnaire.
///
/// Ported from src/features/intake/schemas.js
/// (PHYSICAL_ASSESSMENT_SECTIONS / PROGRAMMING_FLAGS /
/// PROGRAM_STATUS_OPTIONS / GYR_OPTIONS). The keys here are written into
/// `client_records.data.intake.physical` and read back by the web app and by
/// generate-ai-workout-program, which folds `scores`, `observations`,
/// `painScreen`, `programmingFlags` and `coachSummary` into its prompt — so
/// every key below has to match the web spelling exactly or an assessment
/// recorded in one app is invisible to the other.
library;

class PhysicalMovement {
  const PhysicalMovement({required this.key, required this.label});
  final String key;
  final String label;
}

class PhysicalSection {
  const PhysicalSection({
    required this.key,
    required this.title,
    required this.movements,
    this.observations = const [],
    this.photoCheck = false,
  });

  final String key;
  final String title;
  final List<PhysicalMovement> movements;

  /// Quick-pick notes for this pattern. Empty where the section has none.
  final List<String> observations;

  /// Only Posture & Mobility carries the Front/Side/Rear photo checklist.
  final bool photoCheck;
}

const kPhysicalAssessmentSections = [
  PhysicalSection(
    key: "postureMobility",
    title: "Posture & Mobility",
    photoCheck: true,
    movements: [
      PhysicalMovement(key: "toeTouchNarrow", label: "Toe Touch (Narrow Stance)"),
      PhysicalMovement(key: "toeTouchWide", label: "Toe Touch (Wide Stance)"),
      PhysicalMovement(key: "shoulderMobility", label: "Shoulder Mobility (Band Pass-Throughs)"),
    ],
  ),
  PhysicalSection(
    key: "push",
    title: "Push Pattern",
    movements: [
      PhysicalMovement(key: "pushUps", label: "Push-Ups"),
      PhysicalMovement(key: "squatToPress", label: "Squat to Press"),
    ],
  ),
  PhysicalSection(
    key: "pull",
    title: "Pull Pattern",
    movements: [
      PhysicalMovement(key: "bandPullAparts", label: "Band Pull-Aparts"),
      PhysicalMovement(key: "pullUp", label: "Pull-Up Assessment"),
    ],
  ),
  PhysicalSection(
    key: "squat",
    title: "Squat Pattern",
    movements: [
      PhysicalMovement(key: "narrowSquat", label: "Narrow Squat"),
      PhysicalMovement(key: "standardSquat", label: "Standard Squat"),
      PhysicalMovement(key: "wideSquat", label: "Wide Squat"),
    ],
    observations: ["Heel Lift", "Knee Cave", "Limited Depth", "Forward Lean", "Pain", "None"],
  ),
  PhysicalSection(
    key: "hinge",
    title: "Hinge Pattern",
    movements: [PhysicalMovement(key: "hipHinge", label: "Bodyweight Hip Hinge")],
    observations: ["Lumbar Rounding", "Tight Hamstrings", "Poor Hip Loading", "Difficulty Understanding Pattern", "None"],
  ),
  PhysicalSection(
    key: "lunge",
    title: "Lunge Pattern",
    movements: [PhysicalMovement(key: "walkingLunges", label: "Walking Lunges")],
    observations: ["Balance Issues", "Knee Cave", "Short Stride", "Hip Instability", "Pain", "None"],
  ),
  PhysicalSection(
    key: "carry",
    title: "Carry Pattern",
    movements: [PhysicalMovement(key: "suitcaseCarry", label: "Suitcase Carry")],
    observations: ["Leaning", "Balance Issues", "Shoulder Instability", "Core Weakness", "None"],
  ),
  PhysicalSection(
    key: "core",
    title: "Core Stability",
    movements: [
      PhysicalMovement(key: "walkouts", label: "Walkouts"),
      PhysicalMovement(key: "plank", label: "Plank"),
    ],
  ),
];

const kProgrammingFlags = [
  "Shoulder Mobility",
  "Push",
  "Pull",
  "Squat",
  "Hinge",
  "Lunge",
  "Carry",
  "Core Stability",
  "General Deconditioning",
  "No Significant Restrictions",
];

/// Value then label, in the web's order.
const kProgramStatusOptions = [
  ("ready", "Program Ready"),
  ("review", "Requires Management Review"),
  ("medical", "Requires Medical Clearance"),
];

/// The Front/Side/Rear checklist on Posture & Mobility. A record that the
/// photos were taken, not the photos themselves — those go in the client's
/// progress gallery.
const kPhysicalPhotoAngles = ["Front", "Side", "Rear"];

/// Every movement key in the screen, in order — for reading a saved
/// assessment back without walking the section tree.
List<String> get allPhysicalMovementKeys => [
  for (final s in kPhysicalAssessmentSections)
    for (final m in s.movements) m.key,
];

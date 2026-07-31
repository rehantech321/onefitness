/// Mirrors src/constants/domain.js `DISCIPLINES` / `SESSION_TYPES` display
/// labels — trimmed to the values used by the mock trainer data.
const Map<String, String> kDisciplineLabels = {
  "personal-training": "Personal Training",
  "boxing": "Boxing",
  "hike": "Hike",
  "outdoor-hiit": "Outdoor HIIT",
  "stretch": "Stretch",
  "stick-mobility": "Stick Mobility",
  "yoga": "Yoga",
  "programmer": "Programmer",
};

const Map<String, String> kSessionTypeLabels = {
  "semi-private": "Semi-Private",
  "one-on-one": "One-on-One",
  "large-group": "Large Group",
  "assessment-call": "Intake Call",
  "assessment-in-person": "Intake In-Person",
};

String disciplineLabel(String key) => kDisciplineLabels[key] ?? key;
String sessionTypeLabel(String key) => kSessionTypeLabels[key] ?? key;

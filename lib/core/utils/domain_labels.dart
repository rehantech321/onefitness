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
  // The discipline an intake/assessment booking is filed under. "programmer"
  // is the legacy key still on older rows; both read back as "Assessment".
  "assessment": "Assessment",
  "programmer": "Assessment",
};

const Map<String, String> kSessionTypeLabels = {
  "semi-private": "Semi-Private",
  "one-on-one": "One-on-One",
  "large-group": "Large Group",
  "assessment-call": "Intake Call",
  "assessment-in-person": "Intake In-Person",
};

/// Anything the owner adds themselves (Customize Platform → Services) has no
/// entry in the maps above — its key IS its name, so "aerial-yoga" reads back
/// as "Aerial Yoga".
String prettifyKey(String key) => key
    .split(RegExp(r"[-_\s]+"))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(" ");

String disciplineLabel(String key) => kDisciplineLabels[key] ?? prettifyKey(key);
String sessionTypeLabel(String key) => kSessionTypeLabels[key] ?? prettifyKey(key);

/// The key stored for a name the owner typed — lower-case, dash-separated,
/// so it round-trips through [prettifyKey] and is safe in a jsonb list.
String slugifyName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
    .replaceAll(RegExp(r"^-+|-+$"), "");

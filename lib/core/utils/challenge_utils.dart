import "../../data/models/booking.dart";
import "../../data/models/challenge.dart";
import "../../data/models/client_record.dart";

class ChallengeTemplateMeta {
  const ChallengeTemplateMeta({required this.emoji, required this.label, required this.description});
  final String emoji;
  final String label;
  final String description;
}

/// Mirrors challengeHelpers.js `CHALLENGE_TEMPLATES` — trimmed to the two
/// templates the mock data actually uses; unlisted templates fall back to a
/// trophy emoji and score 0, same as the source's own default fallback.
const Map<String, ChallengeTemplateMeta> kChallengeTemplates = {
  "attendance": ChallengeTemplateMeta(
    emoji: "\u{1F3CB}",
    label: "Attendance Challenge",
    description: "Show up the most during the challenge window. Every checked-in session counts toward your score.",
  ),
  "progressive-overload": ChallengeTemplateMeta(
    emoji: "\u{1F4AA}",
    label: "Progressive Overload Challenge",
    description: "Track your biggest single-lift improvement. Log your heaviest set for any exercise and beat your starting weight.",
  ),
};

ChallengeTemplateMeta templateMeta(String key) =>
    kChallengeTemplates[key] ?? const ChallengeTemplateMeta(emoji: "\u{1F3C6}", label: "Challenge", description: "");

bool isClientRegistered(Challenge c, String clientId) => c.participantIds.contains(clientId);

/// Mirrors challengeHelpers.js `calcChallengeScore`, trimmed to the two
/// templates in use: attendance (checked-in sessions in-window) and
/// progressive-overload (highest manually logged value).
double calcChallengeScore(String clientId, Challenge challenge, ClientRecord? clientRecord, List<Booking> bookings) {
  if (challenge.template == "attendance") {
    return bookings
        .where((b) =>
            b.clientId == clientId &&
            b.attendanceStatus == "checked-in" &&
            b.date.compareTo(challenge.startDate) >= 0 &&
            b.date.compareTo(challenge.endDate) <= 0)
        .length
        .toDouble();
  }
  if (challenge.template == "progressive-overload" || challenge.template == "fat-loss") {
    final entries = clientRecord?.challengeProgress[challenge.id] ?? const [];
    if (entries.isEmpty) return 0;
    return entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
  }
  return 0;
}

/// Registration opens 6 days before the challenge starts, closes on start day.
String registrationOpensDate(Challenge c) {
  final d = DateTime.parse(c.startDate).subtract(const Duration(days: 6));
  return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
}

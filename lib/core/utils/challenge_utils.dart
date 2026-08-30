import "../../data/models/booking.dart";
import "../../data/models/challenge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "../../data/models/measurement.dart";
import "date_utils.dart";
import "habit_utils.dart";

class ChallengeTemplateMeta {
  const ChallengeTemplateMeta({
    required this.emoji,
    required this.label,
    required this.metric,
    required this.winnerMode,
    required this.description,
  });
  final String emoji;
  final String label;
  final String metric;
  final String winnerMode; // "auto" | "coach"
  final String description;
}

/// Mirrors challengeHelpers.js `CHALLENGE_TEMPLATES` verbatim (all 8).
const Map<String, ChallengeTemplateMeta> kChallengeTemplates = {
  "attendance": ChallengeTemplateMeta(
    emoji: "\u{1F3CB}\u{FE0F}",
    label: "Attendance Challenge",
    metric: "Sessions attended",
    winnerMode: "auto",
    description: "Show up the most during the challenge window. Every checked-in session counts toward your score.",
  ),
  "fat-loss": ChallengeTemplateMeta(
    emoji: "\u{1F525}",
    label: "Fat Loss Challenge",
    metric: "Lbs lost",
    winnerMode: "auto",
    description: "Track total weight lost from your starting weight. Log your weight regularly to stay on the leaderboard.",
  ),
  "progressive-overload": ChallengeTemplateMeta(
    emoji: "\u{1F4AA}",
    label: "Progressive Overload Challenge",
    metric: "Strength gain (lbs)",
    winnerMode: "auto",
    description: "Track your biggest single-lift improvement. Log your heaviest set for any exercise and beat your starting weight.",
  ),
  "transformation": ChallengeTemplateMeta(
    emoji: "\u{2728}",
    label: "Transformation Challenge",
    metric: "Coach-judged",
    winnerMode: "coach",
    description: "30-day body transformation judged by your coach. Submit a before photo when you join and an after photo at the end.",
  ),
  "30-day": ChallengeTemplateMeta(
    emoji: "\u{1F4C5}",
    label: "30-Day Challenge",
    metric: "Habit consistency %",
    winnerMode: "auto",
    description: "30 days of daily habit completion. Your habit consistency percentage is your score — perfect habits = 100%.",
  ),
  "weight-loss": ChallengeTemplateMeta(
    emoji: "\u{2696}\u{FE0F}",
    label: "Weight Loss Challenge",
    metric: "Lbs lost",
    winnerMode: "auto",
    description: "Track total weight lost during the challenge, straight from your logged measurements — no manual entry needed. Your biggest drop from your starting weight is your score.",
  ),
  "body-fat": ChallengeTemplateMeta(
    emoji: "\u{1F4C9}",
    label: "Body Fat % Challenge",
    metric: "Body fat % lost",
    winnerMode: "auto",
    description: "Track body fat percentage lost during the challenge, straight from your logged measurements. Your biggest drop from your starting body fat % is your score.",
  ),
  "inches-lost": ChallengeTemplateMeta(
    emoji: "\u{1F4CF}",
    label: "Inches Challenge",
    metric: "Inches lost",
    winnerMode: "auto",
    description: "Track total inches lost across chest, waist, hips, arms, and thighs, straight from your logged measurements. Every inch off your starting numbers adds to your score.",
  ),
};

ChallengeTemplateMeta templateMeta(String key) =>
    kChallengeTemplates[key] ??
    const ChallengeTemplateMeta(emoji: "\u{1F3C6}", label: "Challenge", metric: "", winnerMode: "auto", description: "");

bool isClientRegistered(Challenge c, String clientId) => c.participantIds.contains(clientId);

/// Mirrors helpers.js `parseLeadingNum` — measurement fields are free text
/// (e.g. "185" or "185 lbs"), so this pulls the leading numeric portion.
double? _parseLeadingNum(String? s) {
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r"\d+(\.\d+)?").firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

String? _measurementField(Measurement m, String field) {
  switch (field) {
    case "weight":
      return m.weight;
    case "bodyfat":
      return m.bodyfat;
    case "chest":
      return m.chest;
    case "waist":
      return m.waist;
    case "hips":
      return m.hips;
    case "arms":
      return m.arms;
    case "thighs":
      return m.thighs;
    default:
      return null;
  }
}

/// Mirrors challengeHelpers.js `measurementSeries` — this client's logged
/// values for one field within the challenge window, oldest first.
List<double> _measurementSeries(ClientRecord? record, String field, String startDate, String endDate) {
  final entries = (record?.measurements ?? const <Measurement>[])
      .where((m) => m.date.compareTo(startDate) >= 0 && m.date.compareTo(endDate) <= 0)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return entries.map((m) => _parseLeadingNum(_measurementField(m, field))).whereType<double>().toList();
}

/// Mirrors challengeHelpers.js `measurementDrop` — biggest drop from the
/// first logged value in-window to the lowest logged value in-window.
double _measurementDrop(ClientRecord? record, String field, String startDate, String endDate) {
  final series = _measurementSeries(record, field, startDate, endDate);
  if (series.length < 2) return 0;
  final start = series.first;
  final best = series.reduce((a, b) => a < b ? a : b);
  final drop = ((start - best) * 10).round() / 10;
  return drop > 0 ? drop : 0;
}

/// Mirrors challengeHelpers.js `calcChallengeScore` for all 8 templates.
double calcChallengeScore(String clientId, Challenge challenge, ClientRecord? clientRecord, List<Booking> bookings) {
  switch (challenge.template) {
    case "attendance":
      return bookings
          .where((b) =>
              b.clientId == clientId &&
              b.attendanceStatus == "checked-in" &&
              b.date.compareTo(challenge.startDate) >= 0 &&
              b.date.compareTo(challenge.endDate) <= 0)
          .length
          .toDouble();
    case "fat-loss":
    case "progressive-overload":
      final entries = clientRecord?.challengeProgress[challenge.id] ?? const [];
      if (entries.isEmpty) return 0;
      return entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    case "transformation":
      return challenge.winnerClientId == clientId ? 1 : 0;
    case "weight-loss":
      return _measurementDrop(clientRecord, "weight", challenge.startDate, challenge.endDate);
    case "body-fat":
      return _measurementDrop(clientRecord, "bodyfat", challenge.startDate, challenge.endDate);
    case "inches-lost":
      const fields = ["chest", "waist", "hips", "arms", "thighs"];
      return fields.fold(0.0, (total, field) => total + _measurementDrop(clientRecord, field, challenge.startDate, challenge.endDate));
    case "30-day":
    case "community":
      if (clientRecord == null) return 0;
      final habits = getClientHabits(clientRecord);
      if (habits.isEmpty) return 0;
      final start = DateTime.parse(challenge.startDate);
      final today = DateTime.parse(isoToday());
      final challengeEnd = DateTime.parse(challenge.endDate);
      final end = challengeEnd.isBefore(today) ? challengeEnd : today;
      if (end.isBefore(start)) return 0;
      final pcts = <double>[];
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final log = getHabitLog(clientRecord, isoDate(d));
        final done = habits.where((h) => log.checked[h.id] == true).length;
        pcts.add((done / habits.length) * 100);
      }
      if (pcts.isEmpty) return 0;
      return (pcts.reduce((a, b) => a + b) / pcts.length).roundToDouble();
    default:
      return 0;
  }
}

/// Registration opens 6 days before the challenge starts, closes on start day.
String registrationOpensDate(Challenge c) {
  final d = DateTime.parse(c.startDate).subtract(const Duration(days: 6));
  return isoDate(d);
}

/// One ranked leaderboard row.
class RankedParticipant {
  const RankedParticipant({
    required this.clientId,
    required this.name,
    required this.score,
    required this.isWinner,
    required this.rank,
  });
  final String clientId;
  final String name;
  final double score;
  final bool isWinner;
  final int rank;
}

/// Mirrors challengeHelpers.js `rankChallengeParticipants` — the canonical
/// leaderboard + placement builder, shared by the list/detail screens.
List<RankedParticipant> rankChallengeParticipants(
  Challenge challenge,
  List<ClientInfo> roster,
  Map<String, ClientRecord> clientRecords,
  List<Booking> bookings,
) {
  final unranked = challenge.participantIds.map((id) {
    final matches = roster.where((r) => r.id == id);
    final name = matches.isNotEmpty ? matches.first.name : "Unknown";
    final score = calcChallengeScore(id, challenge, clientRecords[id], bookings);
    return (clientId: id, name: name, score: score, isWinner: challenge.winnerClientId == id);
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  var rank = 1;
  final out = <RankedParticipant>[];
  for (var i = 0; i < unranked.length; i++) {
    if (i > 0 && unranked[i].score < unranked[i - 1].score) rank = i + 1;
    final e = unranked[i];
    out.add(RankedParticipant(clientId: e.clientId, name: e.name, score: e.score, isWinner: e.isWinner, rank: rank));
  }
  return out;
}

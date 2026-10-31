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

/// One of the leaderboards a gym-defined challenge type can be ranked by.
///
/// The [key] is deliberately an existing template key: [calcChallengeScore]
/// is a switch over those keys, and reusing them means a custom type runs the
/// same scorer that has been ranking that built-in challenge all along — no
/// new branch, no second implementation to keep in step. [label] is what a
/// coach picks from, which is why it describes the measurement rather than
/// naming the challenge it came from.
class ScoringBasis {
  const ScoringBasis({required this.key, required this.label, required this.detail});
  final String key;
  final String label;
  final String detail;
}

const kScoringBases = [
  ScoringBasis(
    key: "attendance",
    label: "Sessions attended",
    detail: "Counts every session the client checked in to between the start and end dates.",
  ),
  ScoringBasis(
    key: "weight-loss",
    label: "Weight lost (lbs)",
    detail: "Biggest drop from the client's first logged weight in the window. Read from their measurements — nothing to enter by hand.",
  ),
  ScoringBasis(
    key: "body-fat",
    label: "Body fat % lost",
    detail: "Biggest drop from the client's first logged body fat % in the window. Read from their measurements.",
  ),
  ScoringBasis(
    key: "inches-lost",
    label: "Inches lost",
    detail: "Total inches off chest, waist, hips, arms and thighs, from the client's logged measurements.",
  ),
  ScoringBasis(
    key: "30-day",
    label: "Habit consistency %",
    detail: "Average daily habit completion across the window — perfect habits every day scores 100.",
  ),
  ScoringBasis(
    key: "fat-loss",
    label: "A number the client logs",
    detail: "Clients log their own figure against the challenge (a lift, a distance, a weigh-in) and their best entry is their score.",
  ),
];

ScoringBasis? scoringBasisFor(String key) =>
    kScoringBases.where((b) => b.key == key).firstOrNull;

/// Which scorer ranks [c]. A gym-defined type copies its basis onto the
/// challenge at creation; a built-in scores from its own template key, as it
/// always has.
String scoringKey(Challenge c) => c.scoringBasis ?? c.template;

/// Whether [c]'s score is a percentage, and so wants a "%" after it.
bool scoreIsPercent(Challenge c) {
  final key = scoringKey(c);
  return key == "30-day" || key == "community" || key == "body-fat";
}

/// Whether clients have to enter their own figure for [c], rather than it
/// being read from their bookings or measurements.
///
/// Routed through [scoringKey] rather than the template, because a
/// gym-defined type scored this way has its own key: checking the template
/// would leave its participants with a leaderboard they have no way to enter
/// a number for, permanently stuck at zero.
bool needsClientLoggedScore(Challenge c) {
  final key = scoringKey(c);
  return key == "progressive-overload" || key == "fat-loss";
}

/// How a challenge should be presented, wherever it came from.
///
/// Resolved from the challenge row first and the type catalogue second, so a
/// challenge still renders correctly once its gym-defined type is deleted —
/// which is allowed, and must never reach back into challenges already run.
class ChallengeDisplay {
  const ChallengeDisplay({required this.emoji, required this.typeLabel, required this.metric});
  final String emoji;
  final String typeLabel;
  final String metric;
}

ChallengeDisplay challengeDisplay(Challenge c, List<ChallengeTemplate> customTypes) {
  final builtIn = kChallengeTemplates[c.template];
  if (builtIn != null && c.scoringBasis == null) {
    return ChallengeDisplay(emoji: builtIn.emoji, typeLabel: builtIn.label, metric: c.metric);
  }
  final custom = customTypes.where((t) => t.key == c.template).firstOrNull;
  return ChallengeDisplay(
    emoji: c.emoji ?? custom?.emoji ?? "\u{1F3C6}",
    // The type is gone and the challenge never stored its label, so say what
    // is actually known rather than inventing a type name.
    typeLabel: custom?.label ?? "Custom challenge",
    metric: c.metric,
  );
}

/// The types this coach or owner may build a challenge from: every gym-wide
/// one, plus their own. Mirrors how challenges themselves are scoped.
List<ChallengeTemplate> visibleChallengeTypes(List<ChallengeTemplate> all, String? trainerAuth) =>
    all.where((t) => trainerAuth == "owner" || t.trainerId == null || t.trainerId == trainerAuth).toList();

/// Whether [trainerAuth] may delete [t]. The owner manages everything; a
/// coach manages only their own. Mirrors the table's RLS exactly, so the UI
/// never offers an action the database will refuse.
bool canManageChallengeType(ChallengeTemplate t, String? trainerAuth) =>
    trainerAuth == "owner" || (trainerAuth != null && t.trainerId == trainerAuth);

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

/// Mirrors challengeHelpers.js `calcChallengeScore` for all 8 templates, and
/// ranks gym-defined types too — they carry the key of whichever of these
/// scorers they chose, so they arrive here as one of the cases below rather
/// than falling through to 0. See [scoringKey].
double calcChallengeScore(String clientId, Challenge challenge, ClientRecord? clientRecord, List<Booking> bookings) {
  switch (scoringKey(challenge)) {
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

/// Registration opens 6 days before the challenge starts.
String registrationOpensDate(Challenge c) {
  final d = DateTime.parse(c.startDate).subtract(const Duration(days: 6));
  return isoDate(d);
}

/// Whether [c] can still be joined on [today].
///
/// Registration used to close on the start date, which left a running
/// challenge that nobody could enter: a gym's Weight Loss Challenge ran
/// 21 Oct to 11 Nov with a join window of 15–21 Oct, so from the 22nd the
/// Join button was simply gone and the leaderboard stayed empty for the rest
/// of its three weeks. Every client who found the challenge after it started
/// was locked out of it.
///
/// It now stays open until the challenge ends. Joining late carries its own
/// penalty under every scorer this app has — fewer days to drop weight,
/// fewer sessions to attend, fewer habit days to average — so a late entrant
/// takes the disadvantage rather than handing anyone else one.
bool canJoinChallenge(Challenge c, String today) =>
    today.compareTo(registrationOpensDate(c)) >= 0 && today.compareTo(c.endDate) <= 0;

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

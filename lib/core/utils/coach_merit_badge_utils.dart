import "date_utils.dart";
import "habit_utils.dart";
import "report_utils.dart";
import "../../data/models/booking.dart";
import "../../data/models/challenge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "../../data/models/coach_pr_event.dart";
import "../../data/models/comm_message.dart";
import "../../data/models/report_range.dart";
import "../../data/models/trainer.dart";

/// Coach Merit Badge System — pure computation engine. Every function here
/// is a plain, stateless calculation over already-loaded gym-wide state for
/// one calendar-month-shaped [ReportRange]; nothing here writes anywhere
/// (see SupabaseService.finalizeCoachBadgesForMonth for persistence).
///
/// Two badges (Check-In, Comeback) need signals this app has no dedicated
/// event log for — "a client went red" and "the coach followed up" — so
/// both are *derived*, not read off an existing table:
///   - A "red transition" is inferred from a gap of more than 7 days
///     between two consecutive [ClientRecord.workoutLogs] dates (the same
///     7-day rule client_status_utils.dart's `computeClientStatus` uses,
///     just replayed across history instead of anchored to today). The
///     transition date is 8 days after the earlier log; the "return" is
///     the later log's date.
///   - A "check-in completed" is a real chat message from the coach to
///     that client within the 24 hours after a trigger, found via
///     [CommMessage.id] (a `DateTime.now().microsecondsSinceEpoch`
///     string at every write site — the only parseable timestamp on a
///     comm message; `.at` is a display-only stamp() string).
/// Both are disclosed, defensible defaults — nothing elsewhere in the app
/// defines "check-in" or "comeback" more precisely than this.

/// One badge's attainment state for a given coach + range — either the
/// finalized result for a past month, or live in-progress numbers for the
/// current month (never persisted until month-end finalization).
class CoachBadgeProgress {
  const CoachBadgeProgress({
    required this.badgeKey,
    required this.label,
    required this.current,
    required this.target,
    required this.qualifies,
    required this.detail,
  });

  final String badgeKey;
  final String label;
  final int current;
  final int target;
  final bool qualifies;
  final String detail;
}

/// badgeKey -> display label — matches each badge function's own
/// [CoachBadgeProgress.label], kept as a standalone lookup for places that
/// only have a bare badgeKey on hand (e.g. an itemized `coach_merit_badges`
/// history row) and no freshly-computed [CoachBadgeProgress].
const Map<String, String> kCoachBadgeLabels = {
  "full_house": "Full House",
  "pr_factory": "PR Factory",
  "check_in": "Check-In",
  "comeback": "Comeback",
  "habit_coach": "Habit Coach",
  "challenge_coach": "Challenge Coach",
  "coach_of_month": "Coach of the Month",
};

/// Owner-facing description text for each badge — used by My Pay's Coach
/// Merit Badges section (badgeKey -> description).
const Map<String, String> kCoachBadgeDescriptions = {
  "full_house": "90%+ of your booked sessions checked in, with 80%+ of your available capacity booked, this month.",
  "pr_factory": "5+ different clients with a coach-logged PR this month.",
  "check_in": "Followed up with 90%+ of at-risk clients (no-show, back-to-back late cancels, or 7+ days inactive) within 24 hours.",
  "comeback": "2+ clients who went inactive, got a same-day follow-up, returned, and stuck with 3+ sessions in the following two weeks.",
  "habit_coach": "70%+ of your habit-tracking clients hit the consistency bar for several straight weeks this month.",
  "challenge_coach": "50%+ of your roster enrolled in an active challenge this month.",
  "coach_of_month": "Highest composite score across every badge this month, gym-wide.",
};

String _dateOnly(String isoOrTimestamp) => isoOrTimestamp.length >= 10 ? isoOrTimestamp.substring(0, 10) : isoOrTimestamp;

/// A workout-log gap of more than 7 days, replayed across a client's full
/// logged history — see this file's header comment. [transition] is when
/// the client would have flipped to [ClientStatus.red]; [returnDate] is
/// when they logged again.
List<({String transition, String returnDate})> _redTransitionEvents(ClientRecord record) {
  final dates = record.workoutLogs.map((w) => w.date).toSet().toList()..sort();
  final out = <({String transition, String returnDate})>[];
  for (var i = 1; i < dates.length; i++) {
    final gapDays = DateTime.parse(dates[i]).difference(DateTime.parse(dates[i - 1])).inDays;
    if (gapDays > 7) {
      final transition = isoDate(DateTime.parse(dates[i - 1]).add(const Duration(days: 8)));
      out.add((transition: transition, returnDate: dates[i]));
    }
  }
  return out;
}

String? _commMessageDateOnly(CommMessage m) {
  final micros = int.tryParse(m.id);
  if (micros == null) return null;
  return isoDate(DateTime.fromMicrosecondsSinceEpoch(micros));
}

/// True when [record] has a real chat message from [trainerId] to the
/// client, timestamped within the 24 hours starting [triggerDate].
bool _hasCheckInResponse(ClientRecord? record, String trainerId, String triggerDate) {
  if (record == null) return false;
  final windowEnd = isoDate(DateTime.parse(triggerDate).add(const Duration(days: 1)));
  for (final m in record.comms) {
    if (m.who != "trainer" || m.trainerId != trainerId) continue;
    final ts = _commMessageDateOnly(m);
    if (ts != null && ts.compareTo(triggerDate) >= 0 && ts.compareTo(windowEnd) <= 0) return true;
  }
  return false;
}

/// Full House — completion rate + capacity utilization both need to clear
/// the bar; a coach padding one at the expense of the other doesn't qualify.
CoachBadgeProgress fullHouseBadge(
  Trainer coach,
  List<Booking> bookings,
  ReportRange range, {
  int semiPrivateCap = 4,
  double completionBar = 0.90,
  int utilizationBar = 80,
}) {
  final expected = bookings.where((b) => b.trainerId == coach.id && b.status != "cancelled" && range.includes(b.date)).toList();
  final completed = expected.where((b) => b.attendanceStatus == "checked-in").length;
  final utilization = trainerUtilizationInRange(coach, bookings, range, semiPrivateCap: semiPrivateCap);
  final completionRate = expected.isEmpty ? 0.0 : completed / expected.length;
  final utilizationPct = utilization.percent ?? 0;
  return CoachBadgeProgress(
    badgeKey: "full_house",
    label: "Full House",
    current: completed,
    target: expected.length,
    qualifies: expected.isNotEmpty && completionRate >= completionBar && utilizationPct >= utilizationBar,
    detail: expected.isEmpty ? "No sessions booked this month." : "$completed of ${expected.length} sessions checked in · $utilizationPct% capacity booked.",
  );
}

/// PR Factory — distinct clients with a coach-logged PR (see
/// coach_pr_events / the "Log PR" action), not total PR count, so it
/// rewards breadth of coaching rather than one client's streak.
CoachBadgeProgress prFactoryBadge(Trainer coach, List<CoachPrEvent> prEvents, ReportRange range, {int targetClients = 5}) {
  final distinct = prEvents.where((e) => e.trainerId == coach.id && range.includes(_dateOnly(e.earnedAt))).map((e) => e.clientId).toSet().length;
  return CoachBadgeProgress(
    badgeKey: "pr_factory",
    label: "PR Factory",
    current: distinct,
    target: targetClients,
    qualifies: distinct >= targetClients,
    detail: "$distinct client(s) with a logged PR this month.",
  );
}

/// Check-In — every at-risk trigger (no-show, 2+ late-cancels within a
/// trailing 14 days, or a fresh red transition) for this coach's roster in
/// range, and whether each got a real same-window chat follow-up.
CoachBadgeProgress checkInBadge(
  Trainer coach,
  List<ClientInfo> roster,
  Map<String, ClientRecord> clientRecords,
  List<Booking> bookings,
  ReportRange range, {
  double completionBar = 0.90,
}) {
  final myClients = roster.where((c) => c.primaryTrainerId == coach.id).toList();
  var triggerCount = 0;
  var completedCount = 0;
  for (final c in myClients) {
    final record = clientRecords[c.id];
    final triggerDates = <String>{};
    for (final b in bookings.where((b) => b.clientId == c.id && b.trainerId == coach.id && b.attendanceStatus == "no-show" && range.includes(b.date))) {
      triggerDates.add(b.date);
    }
    final lateCancels = bookings.where((b) => b.clientId == c.id && b.trainerId == coach.id && b.attendanceStatus == "late-cancel").map((b) => b.date).toSet().toList()
      ..sort();
    for (final d in lateCancels) {
      final windowStart = isoDate(DateTime.parse(d).subtract(const Duration(days: 14)));
      final countInWindow = lateCancels.where((x) => x.compareTo(windowStart) >= 0 && x.compareTo(d) <= 0).length;
      if (countInWindow >= 2 && range.includes(d)) triggerDates.add(d);
    }
    if (record != null) {
      for (final e in _redTransitionEvents(record)) {
        if (range.includes(e.transition)) triggerDates.add(e.transition);
      }
    }
    for (final d in triggerDates) {
      triggerCount++;
      if (_hasCheckInResponse(record, coach.id, d)) completedCount++;
    }
  }
  final rate = triggerCount > 0 ? completedCount / triggerCount : 0.0;
  return CoachBadgeProgress(
    badgeKey: "check_in",
    label: "Check-In",
    current: completedCount,
    target: triggerCount,
    qualifies: triggerCount > 0 && rate >= completionBar,
    detail: triggerCount == 0 ? "No check-in triggers this month." : "$completedCount of $triggerCount at-risk check-ins followed up within 24h.",
  );
}

/// Comeback — a client who went red, got followed up with, returned, and
/// then actually stuck around (3+ checked-in sessions within 14 days of
/// the return) — the full loop, not just the follow-up message.
CoachBadgeProgress comebackBadge(
  Trainer coach,
  List<ClientInfo> roster,
  Map<String, ClientRecord> clientRecords,
  List<Booking> bookings,
  ReportRange range, {
  int requiredComebacks = 2,
  int sustainDays = 14,
  int sustainSessions = 3,
}) {
  final myClients = roster.where((c) => c.primaryTrainerId == coach.id).toList();
  var qualifying = 0;
  for (final c in myClients) {
    final record = clientRecords[c.id];
    if (record == null) continue;
    for (final e in _redTransitionEvents(record)) {
      if (!range.includes(e.returnDate)) continue;
      if (!_hasCheckInResponse(record, coach.id, e.transition)) continue;
      final windowEnd = isoDate(DateTime.parse(e.returnDate).add(Duration(days: sustainDays)));
      final sustained = bookings
          .where((b) =>
              b.clientId == c.id && b.trainerId == coach.id && b.attendanceStatus == "checked-in" && b.date.compareTo(e.returnDate) >= 0 && b.date.compareTo(windowEnd) <= 0)
          .length;
      if (sustained >= sustainSessions) qualifying++;
    }
  }
  return CoachBadgeProgress(
    badgeKey: "comeback",
    label: "Comeback",
    current: qualifying,
    target: requiredComebacks,
    qualifies: qualifying >= requiredComebacks,
    detail: "$qualifying qualifying client comeback(s) this month.",
  );
}

/// Habit Coach — of the coach's clients who have any habit assigned at
/// all, what share hit the (owner-configured) consistency bar for
/// several straight weekly windows within the month.
CoachBadgeProgress habitCoachBadge(
  Trainer coach,
  List<ClientInfo> roster,
  Map<String, ClientRecord> clientRecords,
  ReportRange range, {
  required int habitPercent,
  required int consecutiveWeeks,
  double coachThreshold = 0.70,
}) {
  final myClients = roster.where((c) => c.primaryTrainerId == coach.id).toList();
  final eligible = <ClientInfo>[];
  for (final c in myClients) {
    final record = clientRecords[c.id];
    if (record != null && getClientHabits(record).isNotEmpty) eligible.add(c);
  }
  if (eligible.isEmpty) {
    return const CoachBadgeProgress(badgeKey: "habit_coach", label: "Habit Coach", current: 0, target: 0, qualifies: false, detail: "No clients with habits assigned.");
  }
  final weekEnds = <String>[];
  var d = DateTime.parse(range.start).add(const Duration(days: 6));
  final end = DateTime.parse(range.end);
  while (!d.isAfter(end)) {
    weekEnds.add(isoDate(d));
    d = d.add(const Duration(days: 7));
  }
  var qualifyingClients = 0;
  for (final c in eligible) {
    final record = clientRecords[c.id]!;
    var streak = 0;
    var best = 0;
    for (final we in weekEnds) {
      if (weeklyScoreForWindow(record, we) >= habitPercent) {
        streak++;
        if (streak > best) best = streak;
      } else {
        streak = 0;
      }
    }
    if (best >= consecutiveWeeks) qualifyingClients++;
  }
  final rate = qualifyingClients / eligible.length;
  return CoachBadgeProgress(
    badgeKey: "habit_coach",
    label: "Habit Coach",
    current: qualifyingClients,
    target: eligible.length,
    qualifies: rate >= coachThreshold,
    detail: "$qualifyingClients of ${eligible.length} clients hit $habitPercent%+ habit consistency for $consecutiveWeeks straight weeks.",
  );
}

/// Challenge Coach — share of the coach's roster enrolled in any challenge
/// active during the month. No active challenge that month = not
/// attainable (shown as such, not silently 0%).
CoachBadgeProgress challengeCoachBadge(
  Trainer coach,
  List<ClientInfo> roster,
  List<Challenge> challenges,
  ReportRange range, {
  double requiredRate = 0.50,
}) {
  final active = challenges.where((ch) => ch.startDate.compareTo(range.end) <= 0 && ch.endDate.compareTo(range.start) >= 0).toList();
  final myClients = roster.where((c) => c.primaryTrainerId == coach.id).toList();
  if (active.isEmpty || myClients.isEmpty) {
    return CoachBadgeProgress(
      badgeKey: "challenge_coach",
      label: "Challenge Coach",
      current: 0,
      target: myClients.length,
      qualifies: false,
      detail: active.isEmpty ? "No active challenge this month." : "No clients assigned.",
    );
  }
  final participantIds = active.expand((ch) => ch.participantIds).toSet();
  final participating = myClients.where((c) => participantIds.contains(c.id)).length;
  final rate = participating / myClients.length;
  return CoachBadgeProgress(
    badgeKey: "challenge_coach",
    label: "Challenge Coach",
    current: participating,
    target: myClients.length,
    qualifies: rate >= requiredRate,
    detail: "$participating of ${myClients.length} clients are in an active challenge.",
  );
}

/// The 6 monthly badges (everything except Coach of the Month, which is
/// cross-coach — see [coachCompositeScore]/[pickCoachOfTheMonth]).
List<CoachBadgeProgress> computeAllCoachBadges({
  required Trainer coach,
  required List<ClientInfo> roster,
  required Map<String, ClientRecord> clientRecords,
  required List<Booking> bookings,
  required List<CoachPrEvent> prEvents,
  required List<Challenge> challenges,
  required ReportRange range,
  required int habitPercent,
  required int habitConsecutiveWeeks,
  int semiPrivateCap = 4,
}) =>
    [
      fullHouseBadge(coach, bookings, range, semiPrivateCap: semiPrivateCap),
      prFactoryBadge(coach, prEvents, range),
      checkInBadge(coach, roster, clientRecords, bookings, range),
      comebackBadge(coach, roster, clientRecords, bookings, range),
      habitCoachBadge(coach, roster, clientRecords, range, habitPercent: habitPercent, consecutiveWeeks: habitConsecutiveWeeks),
      challengeCoachBadge(coach, roster, challenges, range),
    ];

/// One coach's Coach-of-the-Month composite for a month — each sub-rate is
/// that badge's current/target clamped to 0-1 (so exceeding a badge's bar
/// doesn't over-weight the composite).
class CoachCompositeScore {
  const CoachCompositeScore({
    required this.trainer,
    required this.eligible,
    required this.composite,
    required this.fullHouseRate,
    required this.prRate,
    required this.checkInRate,
    required this.comebackRate,
    required this.habitRate,
    required this.challengeRate,
  });

  final Trainer trainer;

  /// Minimum eligibility: >=1 active client and >=5 completed sessions
  /// this month — disclosed default, no threshold given in the spec.
  final bool eligible;
  final double composite;
  final double fullHouseRate;
  final double prRate;
  final double checkInRate;
  final double comebackRate;
  final double habitRate;
  final double challengeRate;
}

double _rateOf(List<CoachBadgeProgress> badges, String key) {
  final b = badges.firstWhere((x) => x.badgeKey == key);
  if (b.target == 0) return 0.0;
  return (b.current / b.target).clamp(0, 1).toDouble();
}

/// Composite = 0.30 Full House + 0.20 PR Factory + 0.20 Check-In +
/// 0.15 Comeback + 0.10 Habit Coach + 0.05 Challenge Coach.
CoachCompositeScore coachCompositeScore(
  Trainer coach,
  List<ClientInfo> roster,
  List<Booking> bookings,
  List<CoachBadgeProgress> badges,
  ReportRange range, {
  int minActiveClients = 1,
  int minCompletedSessions = 5,
}) {
  final fullHouseRate = _rateOf(badges, "full_house");
  final prRate = _rateOf(badges, "pr_factory");
  final checkInRate = _rateOf(badges, "check_in");
  final comebackRate = _rateOf(badges, "comeback");
  final habitRate = _rateOf(badges, "habit_coach");
  final challengeRate = _rateOf(badges, "challenge_coach");
  final activeClients = roster.where((c) => c.primaryTrainerId == coach.id).length;
  final completedSessions = bookings.where((b) => b.trainerId == coach.id && b.attendanceStatus == "checked-in" && range.includes(b.date)).length;
  final composite = 0.30 * fullHouseRate + 0.20 * prRate + 0.20 * checkInRate + 0.15 * comebackRate + 0.10 * habitRate + 0.05 * challengeRate;
  return CoachCompositeScore(
    trainer: coach,
    eligible: activeClients >= minActiveClients && completedSessions >= minCompletedSessions,
    composite: composite,
    fullHouseRate: fullHouseRate,
    prRate: prRate,
    checkInRate: checkInRate,
    comebackRate: comebackRate,
    habitRate: habitRate,
    challengeRate: challengeRate,
  );
}

/// Highest composite among eligible coaches wins; ties broken in the exact
/// spec priority order: prior Coach-of-the-Month wins -> Comeback ->
/// Full House -> Check-In -> Challenge Coach -> Habit Coach -> PR Factory.
/// [priorWinCounts] should be each trainer's historical `coach_of_month`
/// badge count. Returns null if no coach is eligible.
CoachCompositeScore? pickCoachOfTheMonth(List<CoachCompositeScore> scores, {Map<String, int> priorWinCounts = const {}}) {
  final eligible = scores.where((s) => s.eligible).toList();
  if (eligible.isEmpty) return null;
  eligible.sort((a, b) {
    final byComposite = b.composite.compareTo(a.composite);
    if (byComposite != 0) return byComposite;
    final byWins = (priorWinCounts[b.trainer.id] ?? 0).compareTo(priorWinCounts[a.trainer.id] ?? 0);
    if (byWins != 0) return byWins;
    final byComeback = b.comebackRate.compareTo(a.comebackRate);
    if (byComeback != 0) return byComeback;
    final byFullHouse = b.fullHouseRate.compareTo(a.fullHouseRate);
    if (byFullHouse != 0) return byFullHouse;
    final byCheckIn = b.checkInRate.compareTo(a.checkInRate);
    if (byCheckIn != 0) return byCheckIn;
    final byChallenge = b.challengeRate.compareTo(a.challengeRate);
    if (byChallenge != 0) return byChallenge;
    final byHabit = b.habitRate.compareTo(a.habitRate);
    if (byHabit != 0) return byHabit;
    return b.prRate.compareTo(a.prRate);
  });
  return eligible.first;
}

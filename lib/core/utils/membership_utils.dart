import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";
import "date_utils.dart";

/// Session-accounting helpers ported from src/lib/helpers.js and
/// src/data/membershipPlans.js — trimmed to what the client dashboard needs.

/// Mirrors constants/domain.js `GIVE_BACK_ATTENDANCE_STATUSES` — these
/// attendance outcomes hand the session back, so they don't count against
/// the plan. Everything else — including a plain upcoming/not-yet-attended
/// booking, and a no-show — does count, same as the real app. A no-show
/// deliberately costs the client both the fee AND the session itself
/// (Attendance & Cancellation Charging Policy, July 2026) — only a
/// cancellation, early or late, gives the session back.
const kGiveBackAttendanceStatuses = {"early-cancel", "late-cancel"};

/// Every membership or package the client currently holds, in the order
/// booking should draw on them: the recurring membership first (its sessions
/// reset monthly, so unused ones are lost), then packages oldest-first (a
/// lifetime balance keeps).
///
/// A client can hold one recurring membership plus any number of one-time
/// packages at the same time. `membershipPlanId` is only the subscription
/// slot — the one that cancel/freeze/change operate on — so reading it alone
/// misses every package bought alongside. Programs are deliberately not
/// here: they grant programming, not sessions (see isProgramKind).
List<MembershipPlan> heldAccessPlans(ClientInfo info, List<MembershipPlan> allPlans) {
  final byId = {for (final p in allPlans) p.id: p};
  final seen = <String>{};
  final held = <MembershipPlan>[];
  void add(String? id) {
    final p = id == null ? null : byId[id];
    if (p == null || isProgramKind(p.kind) || !seen.add(p.id)) return;
    held.add(p);
  }

  add(info.membershipPlanId);
  final enrolled = [...info.plans.where((e) => e.status == "active")]
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  for (final e in enrolled) {
    add(e.planId);
  }
  // Memberships ahead of packages, keeping start-date order within each —
  // a partition rather than a sort, because List.sort isn't stable.
  return [
    ...held.where((p) => p.kind == PlanKind.membership),
    ...held.where((p) => p.kind != PlanKind.membership),
  ];
}

/// The held plan a staff-made booking should be charged to, or null when
/// the client holds nothing that covers [sessionType].
///
/// Same preference as canBookOffering — membership before packages, first
/// with budget wins — but with one difference: staff can knowingly book a
/// client past their balance, so if every covering plan is spent, the first
/// covering plan is still returned and simply goes over. What must never
/// happen is the booking landing with no plan at all while the client does
/// hold one; that's a session silently not deducted.
String? planToChargeFor(
  ClientInfo info,
  String sessionType,
  List<Booking> bookings,
  List<MembershipPlan> allPlans,
) {
  final covering = heldAccessPlans(info, allPlans)
      .where((p) => sessionType == "large-group" || p.allowedTypes.contains(sessionType))
      .toList();
  if (covering.isEmpty) return null;
  for (final p in covering) {
    if (sessionsUsedThisPeriod(info, p, bookings) < effectiveMaxSessions(info, p)) return p.id;
  }
  return covering.first.id;
}

/// Takes the client's full booking list (not pre-filtered to checked-in —
/// an upcoming booking counts against the plan the moment it's made, only
/// a give-back attendance status or a physical assessment excuses it).
///
/// A booking is charged to the plan it recorded at booking time (`planId`).
/// Rows from before that existed carry none, and fall back to being charged
/// to any plan covering their session type — the only attribution possible
/// for them, and exactly what the app did when they were made.
int sessionsUsedThisPeriod(ClientInfo info, MembershipPlan plan, List<Booking> bookings) {
  final mine = bookings.where((b) =>
      b.clientId == info.id &&
      (b.planId == null ? plan.allowedTypes.contains(b.sessionType) : b.planId == plan.id) &&
      !b.isPhysicalAssessment &&
      !kGiveBackAttendanceStatuses.contains(b.attendanceStatus));
  if (plan.kind == PlanKind.membership) {
    final thisMonth = isoToday().substring(0, 7);
    return mine.where((b) => b.date.substring(0, 7) == thisMonth).length;
  }
  return mine.length; // package: lifetime count against the plan
}

/// Mirrors lib/helpers.js `effectiveMaxSessions` — a membership-kind plan's
/// override goes stale once the calendar rolls into a new month from the
/// one it was set in (sessionCountOverrideMonth), falling back to the
/// plan's own default; a package's override has no month stamp and stays
/// permanent.
int effectiveMaxSessions(ClientInfo info, MembershipPlan plan) {
  final override = info.sessionCountOverride;
  if (override == null) return plan.maxSessions ?? 0;
  final month = info.sessionCountOverrideMonth;
  if (plan.kind == PlanKind.membership && month != null && month != isoToday().substring(0, 7)) {
    return plan.maxSessions ?? 0;
  }
  return override;
}

const _months = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

class TermRenewal {
  const TermRenewal({required this.renewsLabel, required this.termMonths});
  final String renewsLabel;
  final int termMonths;
}

/// Mirrors lib/helpers.js `termRenewal` — rolls forward in whole terms from
/// the plan start date until the term containing today, returning that
/// term's end (= next renewal) date.
TermRenewal? termRenewal(String startDateISO, int termMonths) {
  if (termMonths <= 0) return null;
  var end = DateTime.parse(startDateISO);
  final now = DateTime.parse(isoToday());
  while (!end.isAfter(now)) {
    end = DateTime(end.year, end.month + termMonths, end.day);
  }
  return TermRenewal(
    renewsLabel: "${_months[end.month - 1]} ${end.day}, ${end.year}",
    termMonths: termMonths,
  );
}

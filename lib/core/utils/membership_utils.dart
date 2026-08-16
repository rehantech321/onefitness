import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";
import "date_utils.dart";

/// Session-accounting helpers ported from src/lib/helpers.js and
/// src/data/membershipPlans.js — trimmed to what the client dashboard needs.

/// Mirrors constants/domain.js `GIVE_BACK_ATTENDANCE_STATUSES` — these
/// attendance outcomes hand the session back, so they don't count against
/// the plan. Everything else — including a plain upcoming/not-yet-attended
/// booking — does count, same as the real app.
const kGiveBackAttendanceStatuses = {"early-cancel", "late-cancel", "no-show"};

/// Takes the client's full booking list (not pre-filtered to checked-in —
/// an upcoming booking counts against the plan the moment it's made, only
/// a give-back attendance status or a physical assessment excuses it).
int sessionsUsedThisPeriod(ClientInfo info, MembershipPlan plan, List<Booking> bookings) {
  final mine = bookings.where((b) =>
      b.clientId == info.id &&
      plan.allowedTypes.contains(b.sessionType) &&
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

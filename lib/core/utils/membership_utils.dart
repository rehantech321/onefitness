import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";
import "date_utils.dart";

/// Session-accounting helpers ported from src/lib/helpers.js and
/// src/data/membershipPlans.js — trimmed to what the client dashboard needs.

int sessionsUsedThisPeriod(ClientInfo info, MembershipPlan plan, List<Booking> checkedInBookings) {
  final mine = checkedInBookings.where((b) =>
      b.clientId == info.id &&
      plan.allowedTypes.contains(b.sessionType) &&
      !b.isPhysicalAssessment);
  if (plan.kind == PlanKind.membership) {
    final thisMonth = isoToday().substring(0, 7);
    return mine.where((b) => b.date.substring(0, 7) == thisMonth).length;
  }
  return mine.length; // package: lifetime count against the plan
}

int effectiveMaxSessions(ClientInfo info, MembershipPlan plan) =>
    info.sessionCountOverride ?? (plan.maxSessions ?? 0);

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

import "booking_utils.dart";
import "date_utils.dart";
import "../../data/models/booking.dart";
import "../../data/models/charge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/coach_merit_badge.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/report_range.dart";
import "../../data/models/trainer.dart";

/// Ported from reportHelpers.js / PayrollReports.js — pure local-array
/// aggregation, no backend calls in the source either.

/// Mirrors `presetRange`. [customStart]/[customEnd] are only consulted for
/// `preset == "custom"`, falling back to today when either is missing —
/// same behavior as the web source.
ReportRange presetRange(String preset, {String? customStart, String? customEnd}) {
  final today = isoToday();
  final now = DateTime.parse(today);
  switch (preset) {
    case "today":
      return ReportRange(preset: preset, start: today, end: today);
    case "week":
      final start = now.subtract(Duration(days: now.weekday % 7));
      return ReportRange(preset: preset, start: isoDate(start), end: isoDate(start.add(const Duration(days: 6))));
    case "quarter":
      final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      final start = DateTime(now.year, qStartMonth, 1);
      final end = DateTime(now.year, qStartMonth + 3, 0);
      return ReportRange(preset: preset, start: isoDate(start), end: isoDate(end));
    case "year":
      return ReportRange(preset: preset, start: isoDate(DateTime(now.year, 1, 1)), end: isoDate(DateTime(now.year, 12, 31)));
    case "custom":
      return ReportRange(preset: preset, start: customStart ?? today, end: customEnd ?? today);
    case "month":
    default:
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      return ReportRange(preset: "month", start: isoDate(start), end: isoDate(end));
  }
}

/// Mirrors `estimateSessionRevenue` — a plan's price divided evenly across
/// its session allotment; a synthetic per-session estimate since there's no
/// historical plan-at-booking-time record.
double estimateSessionRevenue(MembershipPlan? plan) {
  if (plan == null || plan.kind == PlanKind.program) return 0;
  final sessions = (plan.maxSessions ?? 0) > 0 ? plan.maxSessions! : 1;
  return plan.priceCents / 100 / sessions;
}

class TrainerRangeStats {
  const TrainerRangeStats({required this.trainer, required this.sessionCount, required this.revenue, required this.uniqueClientCount});
  final Trainer trainer;
  final int sessionCount;
  final double revenue;

  /// Distinct clients this trainer had a session with in range — the unit
  /// the "per client" payout mode pays on (once per client, not once per
  /// session).
  final int uniqueClientCount;

  double get hours => (sessionCount * 60 / 60 * 10).round() / 10;

  /// Session pay under the trainer's chosen $ payout mode — replaces the
  /// old `revenue * commissionRate / 100` formula (Attendance & Cancellation
  /// Charging Policy's sibling change: coach payroll moved from % to $).
  /// Does NOT include referral commission — see [referralCommissionInRange].
  double get commission {
    final rate = trainer.payoutRateCents / 100;
    switch (trainer.payoutMode) {
      case "perHour":
        return hours * rate;
      case "perClient":
        return uniqueClientCount * rate;
      case "perSession":
      default:
        return sessionCount * rate;
    }
  }
}

/// Mirrors `perTrainerInRange` — per-trainer session counts + estimated
/// revenue for every non-staff, non-cancelled booking in range.
List<TrainerRangeStats> perTrainerInRange(List<Trainer> trainers, List<Booking> bookings, List<ClientInfo> roster, List<MembershipPlan> plans, ReportRange range) {
  MembershipPlan? planById(String? id) {
    if (id == null) return null;
    final matches = plans.where((p) => p.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  return trainers.map((t) {
    final sessions = bookings.where((b) => b.trainerId == t.id && b.status != "cancelled" && range.includes(b.date)).toList();
    var revenue = 0.0;
    for (final b in sessions) {
      final client = roster.where((c) => c.id == b.clientId);
      final plan = client.isNotEmpty ? planById(client.first.membershipPlanId) : null;
      revenue += estimateSessionRevenue(plan);
    }
    final uniqueClientCount = sessions.map((b) => b.clientId).toSet().length;
    return TrainerRangeStats(trainer: t, sessionCount: sessions.length, revenue: revenue, uniqueClientCount: uniqueClientCount);
  }).toList();
}

/// Sums this trainer's "referral_commission" charges (Coach Code surcharge,
/// credited by stripe-webhook on a referred client's purchase) in range —
/// a second, separate income stream from [TrainerRangeStats.commission].
double referralCommissionInRange(List<Charge> charges, String trainerId, ReportRange range) => charges
    .where((c) => c.trainerId == trainerId && c.category == "referral_commission" && c.amount != null && range.includes(c.date))
    .fold(0.0, (sum, c) => sum + c.amount!);

/// Sums this trainer's finalized Coach Merit Badge rewards (written by
/// SupabaseService.finalizeCoachBadgesForMonth) whose `period_month` falls
/// inside range — a third, separate income stream alongside
/// [TrainerRangeStats.commission] and [referralCommissionInRange]. Reads
/// straight off `coach_merit_badges` rather than the shared `charges`
/// ledger: unlike every other charge, a badge reward isn't naturally tied
/// to one client (it's earned off aggregate roster activity), and
/// `charges.client_id` is NOT NULL — `reward_cents`/`payout_status` on
/// coach_merit_badges already are exactly the payout-tracking fields this
/// needs, so no client has to be invented to hang a charges row off.
double meritBadgeEarningsInRange(List<CoachMeritBadge> badges, String trainerId, ReportRange range) {
  final months = <String>{};
  var d = DateTime(DateTime.parse(range.start).year, DateTime.parse(range.start).month, 1);
  final end = DateTime.parse(range.end);
  while (!d.isAfter(end)) {
    months.add("${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}");
    d = DateTime(d.year, d.month + 1, 1);
  }
  return badges.where((b) => b.trainerId == trainerId && months.contains(b.periodMonth)).fold(0.0, (sum, b) => sum + b.rewardCents / 100);
}

/// Extracted from (and fixing two bugs found in) attendance_reports.dart's
/// `SessionUtilizationReport`: the original ignored [Trainer.unavailability]
/// (counting capacity on days the coach had blocked off) and ignored
/// [capFor]'s per-slot capacity multiplier (treating every offered slot as
/// capacity 1, so a semi-private/large-group slot's real multi-client
/// capacity was undercounted). Booked-vs-available capacity is the basis
/// for the Full House badge, so it needs to be fair.
class TrainerUtilization {
  const TrainerUtilization({required this.capacity, required this.booked});
  final int capacity;
  final int booked;
  int? get percent => capacity > 0 ? (booked / capacity * 100).round() : null;
}

TrainerUtilization trainerUtilizationInRange(Trainer trainer, List<Booking> bookings, ReportRange range, {int semiPrivateCap = 4}) {
  final start = DateTime.parse(range.start);
  final end = DateTime.parse(range.end);
  var capacity = 0;
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final date = isoDate(d);
    if (fallsInUnavailability(trainer, date)) continue;
    final weekday = d.weekday % 7;
    for (final o in trainerOfferings(trainer, weekday)) {
      capacity += capFor(o.sessionType, semiPrivateCap: semiPrivateCap);
    }
  }
  final booked = bookings.where((b) => b.trainerId == trainer.id && b.status != "cancelled" && range.includes(b.date)).length;
  return TrainerUtilization(capacity: capacity, booked: booked);
}

/// Mirrors `revenueCharges` — charges with a real dollar amount (excludes
/// give-back/no-op entries), filtered to range.
List<Charge> revenueCharges(List<Charge> charges, ReportRange range) => charges.where((c) => c.amount != null && range.includes(c.date)).toList()..sort((a, b) => b.date.compareTo(a.date));

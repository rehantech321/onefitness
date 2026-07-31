import "date_utils.dart";
import "../../data/models/booking.dart";
import "../../data/models/charge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/report_range.dart";
import "../../data/models/trainer.dart";

/// Ported from reportHelpers.js / PayrollReports.js — pure local-array
/// aggregation, no backend calls in the source either.

/// Mirrors `presetRange`.
ReportRange presetRange(String preset) {
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
  const TrainerRangeStats({required this.trainer, required this.sessionCount, required this.revenue});
  final Trainer trainer;
  final int sessionCount;
  final double revenue;
  double get hours => (sessionCount * 60 / 60 * 10).round() / 10;
  double get commission => revenue * trainer.commissionRate / 100;
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
    return TrainerRangeStats(trainer: t, sessionCount: sessions.length, revenue: revenue);
  }).toList();
}

/// Mirrors `revenueCharges` — charges with a real dollar amount (excludes
/// give-back/no-op entries), filtered to range.
List<Charge> revenueCharges(List<Charge> charges, ReportRange range) => charges.where((c) => c.amount != null && range.includes(c.date)).toList()..sort((a, b) => b.date.compareTo(a.date));

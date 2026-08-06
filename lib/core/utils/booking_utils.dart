import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/trainer.dart";
import "date_utils.dart";
import "membership_utils.dart";
import "platform_settings.dart";

/// Booking/scheduling helpers ported from
/// src/features/bookings/schedulingHelpers.js and src/lib/helpers.js —
/// trimmed to what the client-facing booking flow needs.

const kSessionLen = 60; // minutes

/// JS-style weekday: 0=Sunday .. 6=Saturday (matches Date.getDay()).
int weekdayOf(String iso) => DateTime.parse(iso).weekday % 7;

bool isSunday(String iso) => weekdayOf(iso) == 0;

class Offering {
  const Offering({required this.sessionType, required this.discipline, required this.slot});
  final String sessionType;
  final String discipline;
  final int slot;
}

/// Mirrors schedulingHelpers.js `trainerOfferings`.
List<Offering> trainerOfferings(Trainer t, int weekday) {
  final out = <Offering>[];
  for (final block in t.availability) {
    final slots = block.byDay[weekday] ?? const [];
    for (final slot in slots) {
      out.add(Offering(sessionType: block.sessionType, discipline: block.discipline, slot: slot));
    }
  }
  return out;
}

/// Mirrors schedulingHelpers.js `capFor`.
int capFor(String sessionType) {
  if (sessionType == "one-on-one" || sessionType == "assessment-call" || sessionType == "assessment-in-person") return 1;
  if (sessionType == "large-group") return 15;
  return kSemiPrivateCap;
}

/// Mirrors schedulingHelpers.js `bookedCount`.
int bookedCount(List<Booking> bookings, String trainerId, String date, int slot) =>
    bookings.where((b) => b.trainerId == trainerId && b.date == date && b.slot == slot).length;

/// Mirrors schedulingHelpers.js `findTrainerConflict` — another client
/// already occupying this exact trainer+date+slot with an incompatible
/// (1-on-1 capacity) type isn't checked here; we only need the simple
/// same-slot overlap used by the client-booking confirm step.
Booking? findTrainerConflict(List<Booking> bookings, String trainerId, String date, int slot) {
  for (final b in bookings) {
    if (b.trainerId == trainerId && b.date == date && b.slot == slot) return b;
  }
  return null;
}

/// Mirrors lib/helpers.js `cancelWindow`.
String cancelWindow(Booking b) {
  final start = DateTime.parse(b.date).add(Duration(minutes: b.slot));
  final hoursUntil = start.difference(DateTime.now()).inMinutes / 60.0;
  return hoursUntil >= kLateCancellationHours ? "free" : "late";
}

/// Mirrors lib/helpers.js `canReschedule`.
bool canReschedule(Booking b) => !kBlockRescheduleInWindow || cancelWindow(b) == "free";

String lateCancellationFeeLabel() => "\$${(kLateCancellationFeeCents / 100).toStringAsFixed(2)}";

class BookingCheck {
  const BookingCheck({required this.ok, this.reason, this.msg, this.noMembership = false});
  final bool ok;
  final String? reason;
  final String? msg;
  final bool noMembership;
}

/// Mirrors lib/helpers.js `canBookOffering`, trimmed to the checks that
/// matter for a client's own self-service booking flow: membership
/// access + plan type coverage, session budget, lead-time/horizon window,
/// and same-slot self-conflict. Trainer-conflict/capacity are checked
/// separately at confirm time (see findTrainerConflict / bookedCount).
BookingCheck canBookOffering(
  ClientInfo info,
  String sessionType,
  List<Booking> bookings,
  String date,
  int slot,
  MembershipPlan? plan,
) {
  final target = DateTime.parse(date).add(Duration(minutes: slot));
  final hoursAway = target.difference(DateTime.now()).inMinutes / 60.0;
  if (hoursAway < kMinBookingLeadHours) {
    return BookingCheck(ok: false, reason: "lead-time", msg: "Sessions must be booked at least $kMinBookingLeadHours hours in advance.");
  }
  if (hoursAway > kMaxBookingHorizonDays * 24) {
    return BookingCheck(ok: false, reason: "horizon", msg: "You can only book up to $kMaxBookingHorizonDays days in advance.");
  }

  final conflict = bookings.any((b) => b.clientId == info.id && b.date == date && b.slot == slot);
  if (conflict) {
    return const BookingCheck(
      ok: false,
      reason: "conflict",
      msg: "You already have a session booked at this time. Clients can only attend one session per time slot.",
    );
  }

  if (plan == null) {
    return const BookingCheck(ok: false, reason: "no-membership", msg: "You need a membership to book this. Visit the Membership Hub to get started.", noMembership: true);
  }
  if (info.membershipPaused) {
    return const BookingCheck(ok: false, reason: "paused", msg: "Your membership is currently paused — ask your gym to resume it before booking.");
  }
  if (!plan.allowedTypes.contains(sessionType)) {
    return BookingCheck(ok: false, reason: "wrong-type", msg: "Your ${plan.name} doesn't cover this session type.");
  }

  final used = sessionsUsedThisPeriod(info, plan, bookings.where((b) => b.attendanceStatus == "checked-in").toList());
  final max = effectiveMaxSessions(info, plan);
  if (used >= max) {
    final period = plan.kind == PlanKind.membership ? "this month" : "on your package";
    return BookingCheck(ok: false, reason: "budget", msg: "You've used all $max sessions $period.");
  }
  return const BookingCheck(ok: true);
}

const _weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

String weekdayKey(int jsWeekday) => _weekdayKeys[jsWeekday];

String startOfWeek(String iso) => isoDate(DateTime.parse(iso).subtract(Duration(days: weekdayOf(iso))));

String addDaysIso(String iso, int n) => isoDate(DateTime.parse(iso).add(Duration(days: n)));

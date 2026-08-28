import "package:flutter/material.dart";
import "../../data/models/booking.dart";
import "../../data/models/charge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/trainer.dart";
import "../theme/app_colors.dart";
import "date_utils.dart";
import "membership_utils.dart";
import "platform_settings.dart";

/// Booking/scheduling helpers ported from
/// src/features/bookings/schedulingHelpers.js and src/lib/helpers.js —
/// trimmed to what the client-facing booking flow needs.
///
/// These are plain functions (no Riverpod access), so every owner-editable
/// policy they need is an optional parameter defaulting to the matching
/// `core/utils/platform_settings.dart` const — that const is only ever the
/// *fallback* shape now, not the source of truth. Every real UI call site
/// must pass the live value read from `platformSettingsProvider` instead of
/// relying on the default.

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

/// Coach Availability Tab spec's Unavailability check — true when [date]
/// (ISO yyyy-MM-dd) falls inside any of this trainer's marked time-off
/// windows (inclusive both ends). Callers should treat a `true` result
/// exactly like a fully-booked day — no slots offered, not an error — and
/// check this BEFORE calling [trainerOfferings] for that date, since
/// `trainerOfferings` only knows the weekday, not the actual calendar date.
bool fallsInUnavailability(Trainer t, String date) =>
    t.unavailability.any((u) => date.compareTo(u.startDate) >= 0 && date.compareTo(u.endDate) <= 0);

/// Mirrors schedulingHelpers.js `capFor`. [semiPrivateCap] defaults to the
/// hardcoded fallback but should be passed the live
/// `platformSettingsProvider` value from any real UI call site — see this
/// file's own header comment on why the const isn't the source of truth.
int capFor(String sessionType, {int semiPrivateCap = kSemiPrivateCap}) {
  if (sessionType == "one-on-one" || sessionType == "assessment-call" || sessionType == "assessment-in-person") return 1;
  if (sessionType == "large-group") return 15;
  return semiPrivateCap;
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
String cancelWindow(Booking b, {int lateCancellationHours = kLateCancellationHours}) {
  final start = DateTime.parse(b.date).add(Duration(minutes: b.slot));
  final hoursUntil = start.difference(DateTime.now()).inMinutes / 60.0;
  return hoursUntil >= lateCancellationHours ? "free" : "late";
}

/// Mirrors lib/helpers.js `canReschedule`.
bool canReschedule(Booking b, {bool blockRescheduleInWindow = kBlockRescheduleInWindow, int lateCancellationHours = kLateCancellationHours}) =>
    !blockRescheduleInWindow || cancelWindow(b, lateCancellationHours: lateCancellationHours) == "free";

enum CalendarDayStatus { done, missed, upcoming }

/// Mirrors schedulingHelpers.js `calendarDayStatus` — single source of truth
/// for what a client's calendar day "is". Both the Workout Calendar's dot
/// color and tapping a date key off this, so the two can never disagree. A
/// booking marked early-cancel/late-cancel is treated exactly like an empty
/// day — no dot — since the session was given back and nothing meaningful
/// actually happened. A no-show, by contrast, correctly shows as "missed"
/// (it does NOT give the session back — see kGiveBackAttendanceStatuses),
/// same as an unmarked past booking would.
CalendarDayStatus? calendarDayStatus(ClientRecord client, ClientInfo info, List<Booking> bookings, String date) {
  final dayBookings = bookings.where((b) => b.clientId == info.id && b.date == date);
  final logged = client.loggedOn(date);
  final checkedIn = dayBookings.any((b) => b.attendanceStatus == "checked-in");
  if (logged || checkedIn) return CalendarDayStatus.done;
  final hasActiveBooking = dayBookings.any((b) => !kGiveBackAttendanceStatuses.contains(b.attendanceStatus));
  if (!hasActiveBooking) return null;
  return date.compareTo(isoToday()) >= 0 ? CalendarDayStatus.upcoming : CalendarDayStatus.missed;
}

String lateCancellationFeeLabel({int feeCents = kLateCancellationFeeCents}) => "\$${(feeCents / 100).toStringAsFixed(2)}";

/// A booking's `attendanceStatus` value paired with its display label/color —
/// shared between the coach's attendance-marking UI (trainer_home_screen.dart)
/// and the client's own Past Visits history (client_visits_section.dart), so
/// the two can never disagree on what a status is called.
class AttendanceOption {
  const AttendanceOption(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color color;
}

const kAttendanceOptions = [
  AttendanceOption("checked-in", "Check In", AppColors.grn),
  AttendanceOption("early-cancel", "Early Cancel", AppColors.info),
  AttendanceOption("late-cancel", "Late Cancel", AppColors.warning),
  AttendanceOption("no-show", "No Show", AppColors.danger),
];

/// Mirrors the Attendance & Cancellation Charging Policy (July 2026):
/// Late Cancel and No-Show both carry an owner-set fee — but only a
/// no-show also keeps the session (see kGiveBackAttendanceStatuses).
/// Checked In and Early Cancel never charge, so this returns null for
/// anything other than the two feeable statuses. [lateCancellationFeeCents]
/// / [noShowFeeCents] must be the live `platformSettingsProvider` values,
/// not the hardcoded fallback — same reasoning as every other optional
/// param in this file (see header comment).
Charge? attendanceChargeFor(
  Booking b,
  String status, {
  required String clientName,
  String? trainerName,
  int lateCancellationFeeCents = kLateCancellationFeeCents,
  int noShowFeeCents = kNoShowFeeCents,
}) {
  final int cents;
  final String description;
  final String chargeType;
  if (status == "late-cancel") {
    cents = lateCancellationFeeCents;
    description = "Late Cancellation Fee";
    // Not "late-cancel" — the real `charges.type` column has a CHECK
    // constraint allowing only a fixed set of values ("late", "noshow",
    // "manual", "purchase", ...), matching web's own recordChargeIfNeeded
    // (BookSession.jsx), which already writes `type: "late"` for exactly
    // this case.
    chargeType = "late";
  } else if (status == "no-show") {
    cents = noShowFeeCents;
    description = "No-Show Fee";
    chargeType = "noshow";
  } else {
    return null;
  }
  return Charge(
    id: "",
    clientId: b.clientId,
    clientName: clientName,
    type: chargeType,
    date: isoToday(),
    at: stamp(),
    category: "fee",
    description: description,
    amount: cents / 100,
    trainerId: b.trainerId,
    trainerName: trainerName,
  );
}

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
  MembershipPlan? plan, {
  int minBookingLeadHours = kMinBookingLeadHours,
  int maxBookingHorizonDays = kMaxBookingHorizonDays,
}) {
  final target = DateTime.parse(date).add(Duration(minutes: slot));
  final hoursAway = target.difference(DateTime.now()).inMinutes / 60.0;
  if (hoursAway < minBookingLeadHours) {
    return BookingCheck(ok: false, reason: "lead-time", msg: "Sessions must be booked at least $minBookingLeadHours hours in advance.");
  }
  if (hoursAway > maxBookingHorizonDays * 24) {
    return BookingCheck(ok: false, reason: "horizon", msg: "You can only book up to $maxBookingHorizonDays days in advance.");
  }

  final conflict = bookings.any((b) => b.clientId == info.id && b.date == date && b.slot == slot);
  if (conflict) {
    return const BookingCheck(
      ok: false,
      reason: "conflict",
      msg: "You already have a session booked at this time. Clients can only attend one session per time slot.",
    );
  }

  // A coach booking themselves via "Book session — Lead by example" needs
  // no membership at all — mirrors canAccessService/withinBookingLimits
  // both short-circuiting to ok:true for clientInfo.isStaff on the web.
  if (info.isStaff) return const BookingCheck(ok: true);

  if (plan == null) {
    return const BookingCheck(ok: false, reason: "no-membership", msg: "You need a membership to book this. Visit the Membership Hub to get started.", noMembership: true);
  }
  if (info.membershipPaused) {
    return const BookingCheck(ok: false, reason: "paused", msg: "Your membership is currently paused — ask your gym to resume it before booking.");
  }
  if (info.membershipCancelsAt != null && date.compareTo(info.membershipCancelsAt!) > 0) {
    return BookingCheck(ok: false, reason: "membership-ending", msg: "Your membership ends on ${info.membershipCancelsAt} — you can't book sessions after that date.");
  }
  // Large Group classes (Hike, Outdoor HIIT) are included with any active
  // membership — not gated to whichever specific Semi-Private/One-on-One
  // tier the client's plan covers, unlike every other session type. Still
  // subject to the session-budget check below, same as every other type.
  if (sessionType != "large-group" && !plan.allowedTypes.contains(sessionType)) {
    return BookingCheck(ok: false, reason: "wrong-type", msg: "Your ${plan.name} doesn't cover this session type.");
  }

  final used = sessionsUsedThisPeriod(info, plan, bookings);
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

/// Mirrors constants/domain.js `isAssessmentType`.
bool isAssessmentType(String sessionType) => sessionType == "assessment-call" || sessionType == "assessment-in-person";

/// Mirrors lib/format.js `cityFromAddress` — best-effort city extraction
/// from a "Street, City, State ZIP" address string.
String? cityFromAddress(String? address) {
  if (address == null || address.isEmpty) return null;
  final parts = address.split(",");
  return parts.length >= 2 ? parts[1].trim() : address;
}

/// Mirrors AdvancedBookingFlow.jsx `occurrenceDate` — the Nth occurrence of
/// [weekday] on/after [startDate], N weeks later.
String occurrenceDate(String startDate, int weekday, int weekIndex) {
  final startWd = weekdayOf(startDate);
  final diff = (weekday - startWd + 7) % 7;
  return addDaysIso(addDaysIso(startDate, diff), weekIndex * 7);
}

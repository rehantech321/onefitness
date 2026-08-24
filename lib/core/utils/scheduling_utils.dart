import "../../data/models/booking.dart";
import "../../data/models/trainer.dart";

/// Ported from schedulingHelpers.js, trimmed to what the coach-side
/// Scheduling screens need: capacity/conflict checks and weekly-offering
/// lookups, all pure local-array logic (no backend calls in the source
/// either — this is safe to port faithfully).

/// Mirrors `capFor` — default per-session-type capacity. [semiPrivateCap]
/// should be passed the live `platformSettingsProvider` value from any real
/// UI call site — the default here is only the fallback shape (see
/// core/utils/platform_settings.dart).
int capFor(String sessionType, {int semiPrivateCap = 4}) {
  switch (sessionType) {
    case "one-on-one":
      return 1;
    case "semi-private":
      return semiPrivateCap;
    case "large-group":
      return 15;
    default:
      return 1; // assessment-call / assessment-in-person
  }
}

/// One "session" = every booking sharing a trainer + date + slot.
List<Booking> sessionGroup(List<Booking> bookings, String trainerId, String date, int slot) =>
    bookings.where((b) => b.trainerId == trainerId && b.date == date && b.slot == slot).toList();

class CapacityInfo {
  const CapacityInfo({required this.count, required this.cap});
  final int count;
  final int cap;
  bool get atCap => count >= cap;
}

CapacityInfo capacityInfo(List<Booking> bookings, String trainerId, String date, int slot, String sessionType, {int semiPrivateCap = 4}) {
  final group = sessionGroup(bookings, trainerId, date, slot).where((b) => b.status != "cancelled").toList();
  return CapacityInfo(count: group.length, cap: capFor(sessionType, semiPrivateCap: semiPrivateCap));
}

/// Mirrors `findTrainerConflict` — a trainer can only run one session (one
/// type/discipline) per time slot; adding a different type to an occupied
/// slot is a conflict, adding the same type just joins the existing group.
Booking? findTrainerConflict(List<Booking> bookings, String trainerId, String date, int slot, String sessionType, String discipline) {
  final group = sessionGroup(bookings, trainerId, date, slot).where((b) => b.status != "cancelled").toList();
  if (group.isEmpty) return null;
  final mismatch = group.where((b) => b.sessionType != sessionType || b.discipline != discipline);
  return mismatch.isEmpty ? null : mismatch.first;
}

/// Mirrors `trainerOfferings` — every slot start (minutes) this trainer
/// offers on a given weekday (0=Sunday..6=Saturday), across all their
/// availability blocks.
List<({String sessionType, String discipline, int slot})> trainerOfferings(Trainer trainer, int weekday) {
  final out = <({String sessionType, String discipline, int slot})>[];
  for (final block in trainer.availability) {
    for (final slot in block.byDay[weekday] ?? const <int>[]) {
      out.add((sessionType: block.sessionType, discipline: block.discipline, slot: slot));
    }
  }
  return out;
}

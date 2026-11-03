import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "session_move.dart";

/// Carrying out the two drags on the Schedule screen, once [session_move.dart]
/// has said they're allowed.
///
/// Both are written as insert-then-delete rather than an UPDATE of the
/// existing row, matching how a client's own reschedule already works
/// (booking_screen.dart). That isn't a stylistic choice:
/// `trg_enforce_booking_limits` fires BEFORE INSERT only, so an UPDATE that
/// carried a booking into another slot would slip past every capacity and
/// coach-conflict check the database has. Inserting first also means a
/// refusal costs nothing — the original booking is still sitting where it
/// was, and the coach sees why.

/// One client being carried out of their session.
class ClientDragData {
  const ClientDragData({required this.booking, required this.clientName});

  final Booking booking;
  final String clientName;
}

/// A whole session — every booking in one coach+date+slot group — being
/// carried to another date.
class SessionDragData {
  const SessionDragData({required this.group, required this.label});

  final List<Booking> group;

  /// What to show under the finger, e.g. "Semi-Private · 9:00 AM".
  final String label;
}

/// Takes the messenger rather than a [BuildContext] because every caller
/// below speaks after at least one `await`, and the context it started with
/// may be gone by then — the coach can have swiped to another day while the
/// writes were in flight. The messenger is looked up once, before any of
/// that, and still knows whether it's around to show anything.
void _say(ScaffoldMessengerState messenger, String message) {
  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// The one thing staff are allowed to do that the rules say no to: put more
/// people in a room than the limit. Never silent — the count is what it will
/// be once the move lands.
Future<bool> _confirmOverCap(BuildContext context, String detail) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text("Over the class limit"),
      content: Text(detail),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Move anyway")),
      ],
    ),
  );
  return go == true;
}

/// Moves one client from the session they're in into another one.
///
/// The target is described rather than looked up, because a client can also
/// be dropped on a session the owner created that nobody has booked yet —
/// which has no bookings to read a type or duration from.
Future<void> performClientMove(
  BuildContext context,
  WidgetRef ref, {
  required ClientDragData drag,
  required String toTrainerId,
  required String toTrainerName,
  required String toDate,
  required int toSlot,
  required String toSessionType,
  required String toDiscipline,
  required int toDurationMin,
  String? toLocationName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final all = ref.read(allBookingsProvider);
  final settings = ref.read(platformSettingsProvider);
  final isOwner = ref.read(trainerAuthProvider) == "owner";
  final check = checkClientMove(
    all: all,
    booking: drag.booking,
    toTrainerId: toTrainerId,
    toDate: toDate,
    toSlot: toSlot,
    toSessionType: toSessionType,
    toDiscipline: toDiscipline,
    isOwner: isOwner,
    clientName: drag.clientName,
    semiPrivateCap: settings.semiPrivateCap,
  );

  var override = false;
  switch (check) {
    case MoveNoop():
      return;
    case MoveRefused(:final reason):
      _say(messenger, reason);
      return;
    case MoveAllowed(:final needsOverride, :final cap, :final count):
      if (needsOverride) {
        final ok = await _confirmOverCap(
          context,
          "${sessionTypeLabel(toSessionType)} at ${fmtSlot(toSlot)} is limited to $cap. "
          "Moving ${drag.clientName} in makes it ${count + 1} of $cap — more than the limit for this class.",
        );
        if (!ok || !context.mounted) return;
        override = true;
      }
  }

  final original = drag.booking;
  // A move keeps whichever plan the booking was charged to — the client is
  // attending the same thing at a different time, so nothing about what they
  // paid has changed. The exception is landing in a different KIND of
  // session, which their old plan may not cover at all.
  var planId = original.planId;
  if (toSessionType != original.sessionType) {
    final matches = ref.read(trainerRosterProvider).where((c) => c.id == original.clientId);
    planId = matches.isEmpty
        ? null
        : planToChargeFor(matches.first, toSessionType, all, ref.read(membershipPlansProvider));
  }

  final now = DateTime.now().toUtc().toIso8601String();
  try {
    final saved = await SupabaseService.insertBooking(Booking(
      id: "",
      clientId: original.clientId,
      trainerId: toTrainerId,
      date: toDate,
      slot: toSlot,
      sessionType: toSessionType,
      discipline: toDiscipline,
      planId: planId,
      durationMin: toDurationMin,
      locationName: toLocationName ?? original.locationName,
      isPhysicalAssessment: original.isPhysicalAssessment,
      // Only after the owner confirmed above. Without the stamp the booking
      // trigger refuses the insert as over capacity; with it, the trigger
      // also checks the caller really is the owner.
      overriddenBy: override ? "owner" : null,
      overriddenAt: override ? now : null,
      overrideReason: override ? "capacity" : null,
    ));
    final bookings = ref.read(allBookingsProvider.notifier);
    bookings.addBooking(saved);
    // Only now that the new seat exists. The freed one is offered to the
    // waitlist, which is right — it genuinely just opened up.
    await SupabaseService.deleteBooking(original.id);
    bookings.cancelBooking(original.id);
    notifyPush(
      profileId: original.clientId,
      title: "Session moved",
      body: "Your session is now ${niceDate(toDate)} at ${fmtSlot(toSlot)} with $toTrainerName.",
      sms: true,
    );
    if (planId == null && original.planId != null) {
      _say(
        messenger,
        "${drag.clientName} has no active plan covering ${sessionTypeLabel(toSessionType)} — moved, but no session was deducted.",
      );
    } else {
      _say(messenger, "${drag.clientName} moved to ${fmtSlot(toSlot)}.");
    }
  } catch (e) {
    _say(messenger, "Couldn't move ${drag.clientName} — nothing was changed.");
  }
}

/// Moves a whole session to another date, same coach and same time.
Future<void> performSessionMove(
  BuildContext context,
  WidgetRef ref, {
  required SessionDragData drag,
  required String toDate,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(platformSettingsProvider);
  final isOwner = ref.read(trainerAuthProvider) == "owner";
  final check = checkSessionMove(
    all: ref.read(allBookingsProvider),
    group: drag.group,
    toDate: toDate,
    today: isoToday(),
    isOwner: isOwner,
    semiPrivateCap: settings.semiPrivateCap,
  );

  var override = false;
  switch (check) {
    case MoveNoop():
      return;
    case MoveRefused(:final reason):
      _say(messenger, reason);
      return;
    case MoveAllowed(:final needsOverride, :final cap, :final count):
      if (needsOverride) {
        final ok = await _confirmOverCap(
          context,
          "${niceDate(toDate)} at ${fmtSlot(drag.group.first.slot)} already holds $count of $cap. "
          "Moving ${drag.group.length} more there makes it ${count + drag.group.length} — over the limit for this class.",
        );
        if (!ok || !context.mounted) return;
        override = true;
      }
  }

  final now = DateTime.now().toUtc().toIso8601String();
  // Every replacement is created before any original is removed. A class
  // half-moved — three clients on Tuesday and two still on Monday — is worse
  // than one that didn't move, so a failure part-way undoes what it managed
  // and leaves the session exactly where it started.
  final inserted = <Booking>[];
  try {
    for (final b in drag.group) {
      inserted.add(await SupabaseService.insertBooking(Booking(
        id: "",
        clientId: b.clientId,
        trainerId: b.trainerId,
        date: toDate,
        slot: b.slot,
        sessionType: b.sessionType,
        discipline: b.discipline,
        planId: b.planId,
        durationMin: b.durationMin,
        locationName: b.locationName,
        isPhysicalAssessment: b.isPhysicalAssessment,
        overriddenBy: override ? "owner" : null,
        overriddenAt: override ? now : null,
        overrideReason: override ? "capacity" : null,
      )));
    }
  } catch (e) {
    for (final s in inserted) {
      // discardBooking, not deleteBooking: these rows existed for a moment
      // and never freed a real seat, so offering them to the waitlist would
      // hand someone a session that isn't there.
      try {
        await SupabaseService.discardBooking(s.id);
      } catch (_) {}
    }
    _say(messenger, "Couldn't move the session — nothing was changed.");
    return;
  }

  final bookings = ref.read(allBookingsProvider.notifier);
  for (final s in inserted) {
    bookings.addBooking(s);
  }
  for (final b in drag.group) {
    try {
      await SupabaseService.deleteBooking(b.id);
      bookings.cancelBooking(b.id);
    } catch (_) {
      // The replacement is already in place, so the client has their session.
      // A leftover original would show the session on both days; the next
      // full load corrects it, and saying so here would be noise.
    }
    notifyPush(
      profileId: b.clientId,
      title: "Session moved",
      body: "Your session has moved to ${niceDate(toDate)} at ${fmtSlot(b.slot)}.",
      sms: true,
    );
  }
  _say(
    messenger,
    "${drag.label} moved to ${niceDate(toDate)}"
    "${drag.group.length > 1 ? " · ${drag.group.length} clients" : ""}.",
  );
}

/// What a dragged thing looks like under the finger.
///
/// The framework's default for a [Draggable] is the widget itself at full
/// width, which on a phone covers most of what you're trying to aim at. A
/// small gold-edged chip leaves the drop targets visible, and matches how
/// [ReorderableColumn] lifts a row.
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.gold),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: AppColors.gold),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.txt),
            ),
          ],
        ),
      ),
    );
  }
}

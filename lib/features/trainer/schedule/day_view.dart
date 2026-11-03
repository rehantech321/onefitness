import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/booking_utils.dart" show Offering, trainerOfferingsOn;
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/blocked_time.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "add_manual_booking_sheet.dart";
import "block_time_sheet.dart";
import "session_detail_sheet.dart";
import "session_drag.dart";

/// Mirrors DayView.jsx — a day's sessions (grouped by trainer+slot) and
/// blocked-time rows, branching on owner (every coach, grouped) vs coach
/// (their own sessions only).
///
/// Two things here move by press-and-hold, the same gesture the rest of the
/// app reorders by: a client chip on a session card can be dropped on another
/// session to move them into it, and a whole session card can be dropped on
/// the date strip to move it — everyone in it — to another day. Both are the
/// shortcut, never the only way: the detail sheet still adds and removes
/// clients one at a time.
class DayView extends ConsumerWidget {
  const DayView({
    super.key,
    required this.date,
    required this.onOpenClient,
    required this.onPickDate,
  });

  final String date;
  final void Function(String clientId) onOpenClient;

  /// Jumps the whole view to another day — a tap on the date strip.
  final ValueChanged<String> onPickDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    // Kept whole as well as filtered: the date strip counts sessions on the
    // days either side of this one, which the day's own list can't see.
    final visible = ref.watch(allBookingsProvider).where((b) => isOwner || b.trainerId == trainerAuth).toList();
    final bookings = visible.where((b) => b.date == date).toList();
    final blocked = ref.watch(blockedTimesProvider).where((b) => b.date == date && (isOwner || b.trainerId == trainerAuth)).toList();
    final roster = ref.watch(trainerRosterProvider);
    final isPast = date.compareTo(isoToday()) < 0;

    final relevantTrainers = isOwner ? trainers : trainers.where((t) => t.id == trainerAuth).toList();

    // Sessions the owner created for this date that nobody has booked yet —
    // they exist only as availability, so the booking-driven list would
    // never show them.
    final openSessions = {
      for (final t in relevantTrainers)
        t.id: isPast
            ? const <Offering>[]
            : trainerOfferingsOn(t, date)
                .where((o) => o.oneOff && !bookings.any((b) => b.trainerId == t.id && b.slot == o.slot))
                .toList(),
    };
    // A session is one coach at one time slot, however many clients are in
    // it — the same grouping the cards below use. Counting bookings instead
    // showed one 4-person class as "4 sessions".
    final sessionCount = bookings.map((b) => "${b.trainerId}|${b.slot}").toSet().length +
        openSessions.values.fold<int>(0, (n, l) => n + l.length);
    // Distinct people, so a client booked into two classes counts once; a
    // cancelled booking doesn't count them as attending.
    final clientCount = bookings.where((b) => b.status != "cancelled").map((b) => b.clientId).toSet().length;

    final anySession = bookings.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dayLabel(date), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (!isPast && !isOwner)
                TextButton.icon(
                  onPressed: () => showBlockTimeSheet(context, ref, date: date, trainerId: trainerAuth ?? ""),
                  icon: Icon(LucideIcons.lock, size: 13, color: AppColors.mute),
                  label: Text("Block time", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _DateStrip(
            selected: date,
            sessionsByDate: _sessionsByDate(visible),
            onPick: onPickDate,
          ),
          if (anySession && !isPast)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "Press and hold a session to drag it onto another date, or a client to drag them into another session.",
                style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic, height: 1.4),
              ),
            ),
          const SizedBox(height: 12),
          if (isOwner)
            AppCard(
              borderColor: AppColors.goldDim,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$sessionCount session${sessionCount == 1 ? '' : 's'} · $clientCount client${clientCount == 1 ? '' : 's'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          for (final trainer in relevantTrainers) ...[
            if (isOwner) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Row(
                  children: [
                    Avatar(src: trainer.photo, name: trainer.name, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text(trainer.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    if (!isPast)
                      TextButton.icon(
                        onPressed: () => showBlockTimeSheet(context, ref, date: date, trainerId: trainer.id),
                        icon: Icon(LucideIcons.lock, size: 12, color: AppColors.mute),
                        label: Text("Block", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                      ),
                  ],
                ),
              ),
            ],
            _TrainerDaySessions(
              trainerId: trainer.id,
              trainerName: trainer.displayTitle,
              date: date,
              openSessions: openSessions[trainer.id]!,
              bookings: bookings.where((b) => b.trainerId == trainer.id).toList(),
              blocked: blocked.where((b) => b.trainerId == trainer.id).toList(),
              roster: roster,
              isPast: isPast,
              onOpenClient: onOpenClient,
            ),
          ],
          if (bookings.isEmpty && blocked.isEmpty && !relevantTrainers.any((t) => !isPast && trainerOfferingsOn(t, date).any((o) => o.oneOff)))
            const HintBox(text: "Nothing scheduled this day."),
        ],
      ),
    );
  }

  /// How many distinct sessions sit on each date — one coach at one slot is
  /// one session, however many clients are in it.
  Map<String, int> _sessionsByDate(List<Booking> bookings) {
    final keys = <String, Set<String>>{};
    for (final b in bookings) {
      (keys[b.date] ??= {}).add("${b.trainerId}|${b.slot}");
    }
    return {for (final e in keys.entries) e.key: e.value.length};
  }
}

/// The days either side of the one being viewed: a tap moves the view, and a
/// session dropped on one moves that session there.
///
/// This is the drop surface for a session move rather than the month grid,
/// which looks like the obvious place for it. The month cells are a seventh
/// of the screen wide and show start times merged across every coach, so
/// there is nothing in them that identifies one session to pick up, and the
/// targets would be too small to hit with a finger already holding a drag.
class _DateStrip extends ConsumerWidget {
  const _DateStrip({required this.selected, required this.sessionsByDate, required this.onPick});

  final String selected;
  final Map<String, int> sessionsByDate;
  final ValueChanged<String> onPick;

  /// Starts three days before the day being viewed, so the days just gone
  /// are reachable, and runs a fortnight forward — far enough for the moves
  /// staff actually make. Anything further is still a tap away on the month
  /// grid.
  List<String> get _dates {
    final anchor = DateTime.parse(selected).subtract(const Duration(days: 3));
    return [for (var i = 0; i < 15; i++) isoDate(anchor.add(Duration(days: i)))];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = isoToday();
    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final d in _dates)
            _DateCell(
              date: d,
              isSelected: d == selected,
              isToday: d == today,
              isPast: d.compareTo(today) < 0,
              sessions: sessionsByDate[d] ?? 0,
              onPick: onPick,
            ),
        ],
      ),
    );
  }
}

class _DateCell extends ConsumerWidget {
  const _DateCell({
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isPast,
    required this.sessions,
    required this.onPick,
  });

  final String date;
  final bool isSelected;
  final bool isToday;
  final bool isPast;
  final int sessions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = DateTime.parse(date);
    const dow = ["S", "M", "T", "W", "T", "F", "S"];

    return DragTarget<SessionDragData>(
      // A session can't be moved into the past, and dropping it back on the
      // day it already sits on is a no-op — neither should light up as
      // somewhere to aim for.
      onWillAcceptWithDetails: (d) => !isPast && d.data.group.isNotEmpty && d.data.group.first.date != date,
      onAcceptWithDetails: (d) => performSessionMove(context, ref, drag: d.data, toDate: date),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        final border = hot
            ? AppColors.gold
            : isSelected
                ? AppColors.goldDim
                : AppColors.line;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            onTap: () => onPick(date),
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 44,
              decoration: BoxDecoration(
                color: hot
                    ? AppColors.gold.withValues(alpha: 0.18)
                    : isSelected
                        ? AppColors.card
                        : null,
                border: Border.all(color: border, width: hot || isSelected ? 1.5 : 1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dow[parsed.weekday % 7],
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.mute),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${parsed.day}",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isPast
                          ? AppColors.mute
                          : isToday || isSelected
                              ? AppColors.gold
                              : AppColors.txt,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // A dot per session up to three, so a busy day reads as
                  // busy without printing a number this small.
                  SizedBox(
                    height: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < (sessions > 3 ? 3 : sessions); i++)
                          Container(
                            width: 3,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrainerDaySessions extends ConsumerWidget {
  const _TrainerDaySessions({
    required this.trainerId,
    required this.trainerName,
    required this.date,
    required this.openSessions,
    required this.bookings,
    required this.blocked,
    required this.roster,
    required this.isPast,
    required this.onOpenClient,
  });

  final String trainerId;
  final String trainerName;
  final String date;
  final List<Offering> openSessions;
  final List<Booking> bookings;
  final List<BlockedTime> blocked;
  final List<ClientInfo> roster;
  final bool isPast;
  final void Function(String clientId) onOpenClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = bookings.map((b) => b.slot).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in slots)
          _SessionCard(
            trainerId: trainerId,
            trainerName: trainerName,
            date: date,
            slot: slot,
            roster: roster,
            isPast: isPast,
            onOpenClient: onOpenClient,
          ),
        // Created sessions with no client yet. Tapping one opens Book
        // Session with the coach, time and type already filled, so the only
        // thing left to choose is who's going — and a client dragged onto it
        // skips even that.
        for (final o in openSessions)
          _OpenSessionCard(
            trainerId: trainerId,
            trainerName: trainerName,
            date: date,
            offering: o,
          ),
        for (final b in blocked)
          AppCard(
            child: Row(
              children: [
                Icon(LucideIcons.lock, size: 15, color: AppColors.mute),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${b.allDay ? 'All day' : fmtSlot(b.startMin ?? 0)} — Blocked${b.reason != null ? ' · ${b.reason}' : ''}",
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One session: every booking sharing this coach, date and slot.
///
/// Three jobs at once — it opens the detail sheet on a tap, it can be picked
/// up and dropped on a date, and it accepts a client dropped on it. The two
/// drags don't fight: a press-and-hold that lands on a client chip is caught
/// by the chip's own listener, because the innermost recogniser in the
/// gesture arena wins.
class _SessionCard extends ConsumerWidget {
  const _SessionCard({
    required this.trainerId,
    required this.trainerName,
    required this.date,
    required this.slot,
    required this.roster,
    required this.isPast,
    required this.onOpenClient,
  });

  final String trainerId;
  final String trainerName;
  final String date;
  final int slot;
  final List<ClientInfo> roster;
  final bool isPast;
  final void Function(String clientId) onOpenClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read live rather than passed down: a move rewrites the booking list,
    // and this card has to show the result the moment it lands.
    final all = ref.watch(allBookingsProvider);
    final group = sessionGroup(all, trainerId, date, slot);
    if (group.isEmpty) return const SizedBox.shrink();
    final first = group.first;
    final cap = capacityInfo(all, trainerId, date, slot, first.sessionType);
    final label = "${sessionTypeLabel(first.sessionType)} · ${fmtSlot(slot)}";

    final card = DragTarget<ClientDragData>(
      onWillAcceptWithDetails: (d) {
        if (isPast) return false;
        final b = d.data.booking;
        return !(b.trainerId == trainerId && b.date == date && b.slot == slot);
      },
      onAcceptWithDetails: (d) => performClientMove(
        context,
        ref,
        drag: d.data,
        toTrainerId: trainerId,
        toTrainerName: trainerName,
        toDate: date,
        toSlot: slot,
        toSessionType: first.sessionType,
        toDiscipline: first.discipline,
        toDurationMin: first.durationMin,
        toLocationName: first.locationName,
      ),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AppCard(
          borderColor: hot ? AppColors.gold : null,
          onTap: () => showSessionDetailSheet(
            context,
            ref,
            trainerId: trainerId,
            date: date,
            slot: slot,
            onOpenClient: onOpenClient,
          ),
          // Three lines, in the order staff read a session: what it is,
          // who's running it, then when. The clients come under that, so a
          // coach can see who's in the room without opening anything.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sessionTypeLabel(first.sessionType), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text("${disciplineLabel(first.discipline)} · $trainerName", style: TextStyle(fontSize: 12, color: AppColors.txt)),
                        const SizedBox(height: 2),
                        Text(
                          "${dayLabel(date)} · ${fmtSlot(slot)} – ${fmtSlot(slot + first.durationMin)}",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cap.atCap ? AppColors.gold : AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  Tag(text: "${cap.count}/${cap.cap}", gold: cap.atCap),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in group)
                    _ClientChip(
                      booking: b,
                      client: _clientFor(b.clientId),
                      draggable: !isPast,
                    ),
                  if (hot)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.gold),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Drop to move here",
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.gold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (isPast) return card;
    return LongPressDraggable<SessionDragData>(
      data: SessionDragData(group: group, label: label),
      onDragStarted: HapticFeedback.mediumImpact,
      feedback: DragChip(
        label: "$label · ${group.length} client${group.length == 1 ? "" : "s"}",
        icon: LucideIcons.calendar,
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }

  ClientInfo? _clientFor(String id) {
    final matches = roster.where((c) => c.id == id);
    return matches.isEmpty ? null : matches.first;
  }
}

/// A session the owner published that nobody has booked. It has no bookings
/// to read a type from, so the offering supplies them — and a client dropped
/// here is booked straight into it.
class _OpenSessionCard extends ConsumerWidget {
  const _OpenSessionCard({
    required this.trainerId,
    required this.trainerName,
    required this.date,
    required this.offering,
  });

  final String trainerId;
  final String trainerName;
  final String date;
  final Offering offering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<ClientDragData>(
      onWillAcceptWithDetails: (d) {
        final b = d.data.booking;
        return !(b.trainerId == trainerId && b.date == date && b.slot == offering.slot);
      },
      onAcceptWithDetails: (d) => performClientMove(
        context,
        ref,
        drag: d.data,
        toTrainerId: trainerId,
        toTrainerName: trainerName,
        toDate: date,
        toSlot: offering.slot,
        toSessionType: offering.sessionType,
        toDiscipline: offering.discipline,
        toDurationMin: offering.durationMin,
        toLocationName: offering.locationName,
      ),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AppCard(
          borderColor: hot ? AppColors.gold : AppColors.goldDim,
          onTap: () => showAddManualBookingSheet(
            context,
            ref,
            initialDate: date,
            initialTrainerId: trainerId,
            initialSlot: offering.slot,
            initialDurationMin: offering.durationMin,
            initialSessionType: offering.sessionType,
            initialDiscipline: offering.discipline,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sessionTypeLabel(offering.sessionType), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text("${disciplineLabel(offering.discipline)} · $trainerName", style: TextStyle(fontSize: 12, color: AppColors.txt)),
                    const SizedBox(height: 2),
                    Text(
                      "${dayLabel(date)} · ${fmtSlot(offering.slot)} – ${fmtSlot(offering.slot + offering.durationMin)}",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
              Tag(text: hot ? "Drop here" : "Open", gold: true),
              const SizedBox(width: 6),
              Icon(LucideIcons.userPlus, size: 15, color: AppColors.gold),
            ],
          ),
        );
      },
    );
  }
}

/// One client on a session card — and the thing you pick up to move them.
class _ClientChip extends StatelessWidget {
  const _ClientChip({required this.booking, required this.client, required this.draggable});

  final Booking booking;
  final ClientInfo? client;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final name = client?.name ?? "Removed client";
    // First name only: a chip wide enough for "Christopher Mackenzie" fits
    // one per row on a phone, and the avatar already disambiguates.
    final short = name.split(RegExp(r"\s+")).first;

    final chip = Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(src: client?.photo, name: name, size: 20),
          const SizedBox(width: 6),
          Text(short, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    if (!draggable || client == null) return chip;
    return LongPressDraggable<ClientDragData>(
      data: ClientDragData(booking: booking, clientName: name),
      onDragStarted: HapticFeedback.mediumImpact,
      feedback: DragChip(label: name, icon: LucideIcons.user),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: chip,
    );
  }
}

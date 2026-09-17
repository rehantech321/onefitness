import "package:flutter/material.dart";
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
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "add_manual_booking_sheet.dart";
import "block_time_sheet.dart";
import "session_detail_sheet.dart";

/// Mirrors DayView.jsx — a day's sessions (grouped by trainer+slot) and
/// blocked-time rows, branching on owner (every coach, grouped) vs coach
/// (their own sessions only).
class DayView extends ConsumerWidget {
  const DayView({super.key, required this.date, required this.onOpenClient});

  final String date;
  final void Function(String clientId) onOpenClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider).where((b) => b.date == date && (isOwner || b.trainerId == trainerAuth)).toList();
    final blocked = ref.watch(blockedTimesProvider).where((b) => b.date == date && (isOwner || b.trainerId == trainerAuth)).toList();
    final roster = ref.watch(trainerRosterProvider);
    final clientRecords = ref.watch(trainerClientRecordsProvider);
    final isPast = date.compareTo(isoToday()) < 0;

    final relevantTrainers = isOwner ? trainers : trainers.where((t) => t.id == trainerAuth).toList();

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
                  icon: const Icon(LucideIcons.lock, size: 13, color: AppColors.mute),
                  label: const Text("Block time", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isOwner)
            AppCard(
              borderColor: AppColors.goldDim,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${bookings.length} session${bookings.length == 1 ? '' : 's'} · ${bookings.map((b) => b.clientId).toSet().length} clients", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          for (final trainer in relevantTrainers) ...[
            if (isOwner) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Row(
                  children: [
                    Avatar(name: trainer.name, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text(trainer.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    if (!isPast)
                      TextButton.icon(
                        onPressed: () => showBlockTimeSheet(context, ref, date: date, trainerId: trainer.id),
                        icon: const Icon(LucideIcons.lock, size: 12, color: AppColors.mute),
                        label: const Text("Block", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                      ),
                  ],
                ),
              ),
            ],
            _TrainerDaySessions(
              trainerId: trainer.id,
              trainerName: trainer.displayTitle,
              date: date,
              // Sessions the owner created for this date that nobody has
              // booked yet — they exist only as availability, so the
              // booking-driven list below would never show them.
              openSessions: isPast
                  ? const []
                  : trainerOfferingsOn(trainer, date)
                      .where((o) => o.oneOff && !bookings.any((b) => b.trainerId == trainer.id && b.slot == o.slot))
                      .toList(),
              bookings: bookings.where((b) => b.trainerId == trainer.id).toList(),
              blocked: blocked.where((b) => b.trainerId == trainer.id).toList(),
              roster: roster,
              clientRecords: clientRecords,
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
    required this.clientRecords,
    required this.isPast,
    required this.onOpenClient,
  });

  final String trainerId;
  final String trainerName;
  final String date;
  final List<Offering> openSessions;
  final List<Booking> bookings;
  final List<BlockedTime> blocked;
  final List roster;
  final Map clientRecords;
  final bool isPast;
  final void Function(String clientId) onOpenClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = bookings.map((b) => b.slot).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in slots)
          Builder(builder: (context) {
            final group = sessionGroup(bookings, trainerId, date, slot);
            final first = group.first;
            final cap = capacityInfo(bookings, trainerId, date, slot, first.sessionType);
            return AppCard(
              onTap: () => showSessionDetailSheet(
                context,
                ref,
                trainerId: trainerId,
                date: date,
                slot: slot,
                onOpenClient: onOpenClient,
              ),
              // Three lines, in the order staff read a session: what it is,
              // who's running it, then when. Tapping opens the detail sheet
              // where the roster and attendance can be changed.
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sessionTypeLabel(first.sessionType), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text("${disciplineLabel(first.discipline)} · $trainerName", style: const TextStyle(fontSize: 12, color: AppColors.txt)),
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
                  const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
            );
          }),
        // Created sessions with no client yet. Tapping one opens Book
        // Session with the coach, time and type already filled, so the only
        // thing left to choose is who's going.
        for (final o in openSessions)
          AppCard(
            borderColor: AppColors.goldDim,
            onTap: () => showAddManualBookingSheet(
              context,
              ref,
              initialDate: date,
              initialTrainerId: trainerId,
              initialSlot: o.slot,
              initialDurationMin: o.durationMin,
              initialSessionType: o.sessionType,
              initialDiscipline: o.discipline,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sessionTypeLabel(o.sessionType), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text("${disciplineLabel(o.discipline)} · $trainerName", style: const TextStyle(fontSize: 12, color: AppColors.txt)),
                      const SizedBox(height: 2),
                      Text(
                        "${dayLabel(date)} · ${fmtSlot(o.slot)} – ${fmtSlot(o.slot + o.durationMin)}",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.mute),
                      ),
                    ],
                  ),
                ),
                const Tag(text: "Open", gold: true),
                const SizedBox(width: 6),
                const Icon(LucideIcons.userPlus, size: 15, color: AppColors.gold),
              ],
            ),
          ),
        for (final b in blocked)
          AppCard(
            child: Row(
              children: [
                const Icon(LucideIcons.lock, size: 15, color: AppColors.mute),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${b.allDay ? 'All day' : fmtSlot(b.startMin ?? 0)} — Blocked${b.reason != null ? ' · ${b.reason}' : ''}",
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

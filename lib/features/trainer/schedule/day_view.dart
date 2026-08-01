import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/blocked_time.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
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
                    Expanded(child: Text(trainer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
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
              date: date,
              bookings: bookings.where((b) => b.trainerId == trainer.id).toList(),
              blocked: blocked.where((b) => b.trainerId == trainer.id).toList(),
              roster: roster,
              clientRecords: clientRecords,
              isPast: isPast,
              onOpenClient: onOpenClient,
            ),
          ],
          if (bookings.isEmpty && blocked.isEmpty) const HintBox(text: "Nothing scheduled this day."),
        ],
      ),
    );
  }
}

class _TrainerDaySessions extends ConsumerWidget {
  const _TrainerDaySessions({
    required this.trainerId,
    required this.date,
    required this.bookings,
    required this.blocked,
    required this.roster,
    required this.clientRecords,
    required this.isPast,
    required this.onOpenClient,
  });

  final String trainerId;
  final String date;
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
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(fmtSlot(slot), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cap.atCap ? AppColors.gold : AppColors.txt)),
                  ),
                  Expanded(
                    child: Text("${sessionTypeLabel(first.sessionType)} · ${disciplineLabel(first.discipline)}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  ),
                  Tag(text: "${cap.count}/${cap.cap}", gold: cap.atCap),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
            );
          }),
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

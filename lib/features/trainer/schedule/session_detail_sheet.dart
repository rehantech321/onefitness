import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "client_search_picker.dart";

/// Mirrors SessionDetail.jsx — the roster of every client in one
/// trainer+date+slot group, with add/remove-client and cancel actions.
Future<void> showSessionDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required String trainerId,
  required String date,
  required int slot,
  required void Function(String clientId) onOpenClient,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _SessionDetailBody(trainerId: trainerId, date: date, slot: slot, onOpenClient: onOpenClient),
    ),
  );
}

class _SessionDetailBody extends ConsumerStatefulWidget {
  const _SessionDetailBody({required this.trainerId, required this.date, required this.slot, required this.onOpenClient});
  final String trainerId;
  final String date;
  final int slot;
  final void Function(String clientId) onOpenClient;

  @override
  ConsumerState<_SessionDetailBody> createState() => _SessionDetailBodyState();
}

class _SessionDetailBodyState extends ConsumerState<_SessionDetailBody> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final allBookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final trainers = ref.watch(trainersProvider);
    final active = sessionGroup(allBookings, widget.trainerId, widget.date, widget.slot);
    if (active.isEmpty) return const SizedBox.shrink();
    final first = active.first;
    final cap = capacityInfo(allBookings, widget.trainerId, widget.date, widget.slot, first.sessionType);
    final trainerName = trainers.where((t) => t.id == widget.trainerId).isNotEmpty ? trainers.firstWhere((t) => t.id == widget.trainerId).name : "Coach";
    final isPast = widget.date.compareTo(isoToday()) < 0;

    if (_adding) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackBar(onBack: () => setState(() => _adding = false), title: "Add a client"),
            const SizedBox(height: 10),
            ClientSearchPicker(
              roster: roster,
              exclude: active.map((b) => b.clientId).toList(),
              onSelect: (c) {
                ref.read(allBookingsProvider.notifier).addBooking(Booking(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      clientId: c.id,
                      trainerId: widget.trainerId,
                      date: widget.date,
                      slot: widget.slot,
                      sessionType: first.sessionType,
                      discipline: first.discipline,
                    ));
                setState(() => _adding = false);
              },
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fmtSlot(widget.slot), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text("${dayLabel(widget.date)} · $trainerName · ${sessionTypeLabel(first.sessionType)} · ${disciplineLabel(first.discipline)}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
          const SizedBox(height: 6),
          Tag(text: "${cap.count}/${cap.cap}", gold: !cap.atCap),
          const SizedBox(height: 14),
          ...active.map((b) {
            final matches = roster.where((c) => c.id == b.clientId);
            final client = matches.isNotEmpty ? matches.first : null;
            return AppCard(
              child: Row(
                children: [
                  Avatar(name: client?.name ?? "Removed", size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: client != null
                          ? () {
                              Navigator.of(context).pop();
                              widget.onOpenClient(client.id);
                            }
                          : null,
                      child: Text(client?.name ?? "Removed client", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  if (!isPast)
                    IconButton(
                      onPressed: () => ref.read(allBookingsProvider.notifier).cancelBooking(b.id),
                      icon: const Icon(LucideIcons.userMinus, size: 15, color: Color(0xFF6B3B3B)),
                    ),
                ],
              ),
            );
          }),
          if (!isPast) ...[
            const SizedBox(height: 6),
            BtnGhost(full: true, onPressed: () => setState(() => _adding = true), child: const Text("Add a client")),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: active.isEmpty
                  ? null
                  : () {
                      for (final b in active) {
                        ref.read(allBookingsProvider.notifier).cancelBooking(b.id);
                      }
                      Navigator.of(context).pop();
                    },
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), side: const BorderSide(color: Color(0xFF8B3B3B)), minimumSize: const Size.fromHeight(44)),
              child: const Text("Cancel session"),
            ),
          ],
        ],
      ),
    );
  }
}

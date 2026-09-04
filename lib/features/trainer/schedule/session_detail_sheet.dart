import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
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
  bool _busy = false;

  void _showError() {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
  }

  @override
  Widget build(BuildContext context) {
    final allBookings = ref.watch(allBookingsProvider);
    final roster = ref.watch(trainerRosterProvider);
    final trainers = ref.watch(trainersProvider);
    final settings = ref.watch(platformSettingsProvider);
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
              onSelect: (c) async {
                setState(() => _adding = false);
                try {
                  final saved = await SupabaseService.insertBooking(Booking(
                        id: "",
                        clientId: c.id,
                        trainerId: widget.trainerId,
                        date: widget.date,
                        slot: widget.slot,
                        sessionType: first.sessionType,
                        discipline: first.discipline,
                      ));
                  ref.read(allBookingsProvider.notifier).addBooking(saved);
                } catch (e) {
                  _showError();
                }
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await SupabaseService.deleteBooking(b.id);
                                    ref.read(allBookingsProvider.notifier).cancelBooking(b.id);
                                    notifyPush(profileId: b.clientId, title: "Appointment canceled", body: "Your session on ${niceDate(b.date)} at ${fmtSlot(b.slot)} was canceled.");
                                  } catch (e) {
                                    _showError();
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          icon: const Icon(LucideIcons.userMinus, size: 15, color: Color(0xFF6B3B3B)),
                        ),
                    ],
                  ),
                  if (client != null) ...[
                    const SizedBox(height: 9),
                    if (b.attendanceStatus != null)
                      _MarkedAttendanceTag(status: b.attendanceStatus!)
                    else
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: kAttendanceOptions.map((opt) {
                          return InkWell(
                            onTap: () {
                              ref.read(allBookingsProvider.notifier).updateAttendance(b.id, opt.key);
                              SupabaseService.updateBookingAttendance(b.id, opt.key).catchError((Object _) {
                                ref.read(allBookingsProvider.notifier).updateAttendance(b.id, null);
                              });
                              if (opt.key == "checked-in") {
                                final total = ref.read(allBookingsProvider).where((x) => x.clientId == client.id && x.attendanceStatus == "checked-in").length;
                                notifySessionMilestoneIfCrossed(toEmail: client.email ?? "", toName: client.name, totalCheckedIn: total, profileId: client.id);
                              }
                              final charge = attendanceChargeFor(
                                b,
                                opt.key,
                                clientName: client.name,
                                trainerName: trainerName,
                                lateCancellationFeeCents: settings.lateCancellationFeeCents,
                                noShowFeeCents: settings.noShowFeeCents,
                              );
                              if (charge != null) {
                                SupabaseService.insertCharge(charge).then(
                                  (saved) => ref.read(chargesProvider.notifier).add(saved),
                                ).catchError((Object e) {
                                  // ignore: avoid_print
                                  print("[attendance charge] failed to save: $e");
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(7),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.line),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(opt.label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.mute)),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ],
              ),
            );
          }),
          if (!isPast) ...[
            const SizedBox(height: 6),
            BtnGhost(full: true, onPressed: () => setState(() => _adding = true), child: const Text("Add a client")),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: active.isEmpty || _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        for (final b in active) {
                          await SupabaseService.deleteBooking(b.id);
                          ref.read(allBookingsProvider.notifier).cancelBooking(b.id);
                          notifyPush(profileId: b.clientId, title: "Appointment canceled", body: "Your session on ${niceDate(b.date)} at ${fmtSlot(b.slot)} was canceled.");
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (e) {
                        _showError();
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), side: const BorderSide(color: Color(0xFF8B3B3B)), minimumSize: const Size.fromHeight(44)),
              child: Text(_busy ? "Cancelling…" : "Cancel session"),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown in place of the attendance-option buttons once a client's booking
/// already has a status — mirrors the user's explicit ask: "If the client
/// is already marked then no options will appear."
class _MarkedAttendanceTag extends StatelessWidget {
  const _MarkedAttendanceTag({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final opt = kAttendanceOptions.firstWhere((o) => o.key == status, orElse: () => kAttendanceOptions.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: opt.color), borderRadius: BorderRadius.circular(6)),
      child: Text(opt.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: opt.color)),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/waitlist_entry.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ManageWaitlist.jsx (owner-only) — pending-approval requests from
/// the client-side recurring "Advanced Booking" flow, grouped by client.
/// A separate status ("waiting", single-slot join-a-full-session requests)
/// lives in the same table but never needs approval, so it never appears
/// here.
class WaitlistScreen extends ConsumerStatefulWidget {
  const WaitlistScreen({super.key});

  @override
  ConsumerState<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends ConsumerState<WaitlistScreen> {
  String? _busyId;
  String? _err;

  Future<void> _approve(WaitlistEntry w) async {
    setState(() {
      _busyId = w.id;
      _err = null;
    });
    try {
      final bookings = ref.read(allBookingsProvider);
      final semiPrivateCap = ref.read(platformSettingsProvider).semiPrivateCap;
      final stillOpen = bookedCount(bookings, w.trainerId, w.date, w.slot) < capFor(w.sessionType, semiPrivateCap: semiPrivateCap);
      if (stillOpen) {
        final saved = await SupabaseService.insertBooking(Booking(
          id: "",
          clientId: w.clientId,
          trainerId: w.trainerId,
          date: w.date,
          slot: w.slot,
          sessionType: w.sessionType,
          discipline: w.discipline ?? "",
        ));
        ref.read(allBookingsProvider.notifier).addBooking(saved);
      }
      await SupabaseService.deleteWaitlistEntry(w.id);
      ref.read(waitlistProvider.notifier).remove(w.id);
      if (!stillOpen && mounted) {
        setState(() => _err = "That session filled up before you approved it — no booking was made.");
      }
    } catch (e) {
      if (mounted) setState(() => _err = "Couldn't approve that request — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _decline(WaitlistEntry w) async {
    setState(() {
      _busyId = w.id;
      _err = null;
    });
    try {
      await SupabaseService.deleteWaitlistEntry(w.id);
      ref.read(waitlistProvider.notifier).remove(w.id);
    } catch (e) {
      if (mounted) setState(() => _err = "Couldn't decline that request — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    // A coach sees the queue for their own sessions; the owner sees the
    // whole gym's. Scoped here rather than in the query so both roles share
    // one screen.
    final waitlist = ref
        .watch(waitlistProvider)
        .where((w) => isOwner || w.trainerId == trainerAuth)
        .toList();
    final pending = waitlist.where((w) => w.status == "pending-approval").toList();

    // Single-slot waiters: people queued for a session that was full, and
    // whoever currently holds an offer on a slot that freed up.
    final queued = waitlist.where((w) => w.status == "waiting" || w.status == "offered").toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        final bySlot = a.slot.compareTo(b.slot);
        if (bySlot != 0) return bySlot;
        return (a.position ?? 9999).compareTo(b.position ?? 9999);
      });
    final bySlotKey = <String, List<WaitlistEntry>>{};
    for (final w in queued) {
      bySlotKey.putIfAbsent("${w.trainerId}|${w.date}|${w.slot}", () => []).add(w);
    }
    final bySeries = <String, List<WaitlistEntry>>{};
    for (final w in pending) {
      bySeries.putIfAbsent(w.seriesId ?? w.id, () => []).add(w);
    }
    final groups = bySeries.entries.toList()..sort((a, b) => (a.value.first.requestedAt ?? "").compareTo(b.value.first.requestedAt ?? ""));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel("Waiting for a spot"),
          const HintBox(
            text: "Clients queued for sessions that were full. When a booking is cancelled the top of the queue is "
                "automatically offered the slot, and it passes down the line if they decline or don't answer.",
          ),
          if (bySlotKey.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: HintBox(text: "Nobody's waiting on a full session right now."),
            )
          else
            ...bySlotKey.entries.map((g) => _QueuedSlotCard(entries: g.value)),
          const SizedBox(height: 22),
          const SectionLabel("Advanced Booking requests"),
          const HintBox(text: "Requests from clients' Advanced Booking, waiting on your approval before they become real bookings."),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_err!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12)),
            ),
          if (groups.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 12), child: HintBox(text: "No pending waitlist requests."))
          else
            ...groups.map((group) {
              final entries = group.value;
              final first = entries.first;
              return AppCard(
                margin: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(src: null, name: first.clientName, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(first.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text(
                                "with ${first.trainerName} · ${entries.length} request${entries.length != 1 ? "s" : ""}",
                                style: const TextStyle(fontSize: 11, color: AppColors.mute),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ...entries.map((w) {
                      final busy = _busyId == w.id;
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${w.date} · ${fmtSlot(w.slot)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(
                                    "${sessionTypeLabel(w.sessionType)} · ${w.discipline != null ? disciplineLabel(w.discipline!) : ""}",
                                    style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                  ),
                                ],
                              ),
                            ),
                            _WaitlistActionBtn(
                              icon: LucideIcons.check,
                              label: "Approve",
                              color: AppColors.gold,
                              onTap: busy ? null : () => _approve(w),
                            ),
                            const SizedBox(width: 6),
                            _WaitlistActionBtn(
                              icon: LucideIcons.x,
                              label: "Decline",
                              color: const Color(0xFFC97F7F),
                              onTap: busy ? null : () => _decline(w),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _WaitlistActionBtn extends StatelessWidget {
  const _WaitlistActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: disabled ? AppColors.line : color),
          color: color == AppColors.gold ? AppColors.gold.withValues(alpha: disabled ? 0.05 : 0.15) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: disabled ? AppColors.mute : color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: disabled ? AppColors.mute : color)),
          ],
        ),
      ),
    );
  }
}


/// One full slot and everyone queued for it, in order. Grouped by slot
/// rather than listed flat so it's obvious at a glance which sessions are
/// in demand and who's next if someone drops out.
class _QueuedSlotCard extends StatelessWidget {
  const _QueuedSlotCard({required this.entries});

  final List<WaitlistEntry> entries;

  @override
  Widget build(BuildContext context) {
    final first = entries.first;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${dayLabel(first.date)} · ${fmtSlot(first.slot)}",
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              Text(
                "${entries.length} waiting",
                style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(
            "${first.trainerName} · ${first.sessionType}",
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
          const SizedBox(height: 8),
          ...entries.asMap().entries.map((e) {
            final i = e.key;
            final w = e.value;
            final offered = w.isLiveOffer;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      "${i + 1}.",
                      style: const TextStyle(fontSize: 11.5, color: AppColors.mute, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      w.clientName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: offered ? FontWeight.w700 : FontWeight.w500,
                        color: offered ? AppColors.gold : AppColors.txt,
                      ),
                    ),
                  ),
                  if (offered)
                    const Text(
                      "OFFERED",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 0.5),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

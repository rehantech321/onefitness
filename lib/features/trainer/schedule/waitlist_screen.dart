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
      final stillOpen = bookedCount(bookings, w.trainerId, w.date, w.slot) < capFor(w.sessionType);
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
    final waitlist = ref.watch(waitlistProvider);
    final pending = waitlist.where((w) => w.status == "pending-approval").toList();
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
          const SectionLabel("Waitlist"),
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

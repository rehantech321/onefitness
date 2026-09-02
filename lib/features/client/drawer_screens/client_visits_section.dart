import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../booking/booking_cancel_screen.dart";

/// New "Visits" entry inside Profile Settings — toggles between past
/// sessions (with their attendance outcome, from kAttendanceOptions) and
/// upcoming ones (with an Edit menu offering Reschedule/Cancel). The cancel
/// flow mirrors day_detail_screen.dart's/booking_screen.dart's own
/// `_confirmCancel` exactly (same delete + late-cancel charge logic);
/// Reschedule reuses client_shell.dart's `startReschedule` so it lands on
/// the same booking picker every other Reschedule entry point uses.
class ClientVisitsSection extends ConsumerStatefulWidget {
  const ClientVisitsSection({
    super.key,
    required this.onBack,
    required this.onReschedule,
  });

  final VoidCallback onBack;
  final ValueChanged<Booking> onReschedule;

  @override
  ConsumerState<ClientVisitsSection> createState() =>
      _ClientVisitsSectionState();
}

class _ClientVisitsSectionState extends ConsumerState<ClientVisitsSection> {
  String _tab = "future"; // "future" | "past"
  Booking? _cancelTarget;
  bool _busy = false;
  String? _error;

  Future<void> _confirmCancel() async {
    if (_busy) return;
    final b = _cancelTarget!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.deleteBooking(b.id);
      ref.read(clientBookingsProvider.notifier).cancelBooking(b.id);
      // A client cancelling their own booking can only ever be "free" or
      // "late" — a no-show is by definition something the client never
      // reported, so self-cancel never produces one (see cancelWindow).
      final settings = ref.read(platformSettingsProvider);
      if (cancelWindow(b, lateCancellationHours: settings.lateCancellationHours) != "free") {
        final info = ref.read(clientInfoProvider);
        final trainer = ref.read(trainersProvider).where((t) => t.id == b.trainerId);
        final charge = attendanceChargeFor(
          b,
          "late-cancel",
          clientName: info.name,
          trainerName: trainer.isNotEmpty ? trainer.first.name : null,
          lateCancellationFeeCents: settings.lateCancellationFeeCents,
          noShowFeeCents: settings.noShowFeeCents,
        );
        if (charge != null) {
          SupabaseService.insertCharge(charge).then((saved) => ref.read(chargesProvider.notifier).add(saved)).catchError((Object e) {
            // ignore: avoid_print
            print("[cancel charge] failed to save: $e");
          });
        }
      }
      setState(() {
        _busy = false;
        _cancelTarget = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't cancel that session — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider);

    if (_cancelTarget != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _cancelTarget = null),
        child: Column(
          children: [
            Expanded(
              child: BookingCancelScreen(
                booking: _cancelTarget!,
                trainers: trainers,
                onBack: () => setState(() => _cancelTarget = null),
                onConfirmCancel: _confirmCancel,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
              ),
          ],
        ),
      );
    }

    final info = ref.watch(clientInfoProvider);
    final settings = ref.watch(platformSettingsProvider);
    final bookings = ref.watch(clientBookingsProvider).where((b) => b.clientId == info.id).toList();
    final today = isoToday();

    final future = bookings.where((b) => b.date.compareTo(today) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0')).compareTo(b.date + b.slot.toString().padLeft(4, '0')));
    final past = bookings.where((b) => b.date.compareTo(today) < 0).toList()
      ..sort((a, b) => (b.date + b.slot.toString().padLeft(4, '0')).compareTo(a.date + a.slot.toString().padLeft(4, '0')));

    Trainer? trainerFor(Booking b) {
      final matches = trainers.where((t) => t.id == b.trainerId);
      return matches.isNotEmpty ? matches.first : null;
    }

    bool canRescheduleNow(Booking b) => canReschedule(
          b,
          blockRescheduleInWindow: settings.blockRescheduleInWindow,
          lateCancellationHours: settings.lateCancellationHours,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile Settings"),
          const SizedBox(height: 10),
          const SectionLabel("Visits"),
          Row(
            children: [
              Expanded(
                child: _VisitsTab(
                  label: "Future Visits",
                  selected: _tab == "future",
                  onTap: () => setState(() => _tab = "future"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VisitsTab(
                  label: "Past Visits",
                  selected: _tab == "past",
                  onTap: () => setState(() => _tab = "past"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_tab == "future")
            if (future.isEmpty)
              const HintBox(text: "No upcoming sessions booked.")
            else
              ...future.map(
                (b) => _FutureVisitCard(
                  booking: b,
                  trainer: trainerFor(b),
                  reschedulable: canRescheduleNow(b),
                  charged: cancelWindow(b, lateCancellationHours: settings.lateCancellationHours) != "free",
                  onReschedule: () => widget.onReschedule(b),
                  onCancel: () => setState(() => _cancelTarget = b),
                ),
              )
          else if (past.isEmpty)
            const HintBox(text: "No past sessions yet.")
          else
            ...past.map((b) => _PastVisitCard(booking: b, trainer: trainerFor(b))),
        ],
      ),
    );
  }
}

class _VisitsTab extends StatelessWidget {
  const _VisitsTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.gold : AppColors.mute,
          ),
        ),
      ),
    );
  }
}

class _FutureVisitCard extends StatelessWidget {
  const _FutureVisitCard({
    required this.booking,
    required this.trainer,
    required this.reschedulable,
    required this.charged,
    required this.onReschedule,
    required this.onCancel,
  });

  final Booking booking;
  final Trainer? trainer;
  final bool reschedulable;
  final bool charged;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${dayLabel(b.date)} · ${fmtSlot(b.slot)}",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(trainer?.name ?? "Removed", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  if (charged)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        "⚠ Late cancel fee window",
                        style: TextStyle(fontSize: 11, color: Color(0xFFD68A4F), fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              color: AppColors.card,
              onSelected: (v) => v == "reschedule" ? onReschedule() : onCancel(),
              itemBuilder: (context) => [
                if (reschedulable)
                  const PopupMenuItem(
                    value: "reschedule",
                    child: Text("Reschedule", style: TextStyle(color: AppColors.txt, fontSize: 13)),
                  ),
                PopupMenuItem(
                  value: "cancel",
                  child: Text(
                    charged ? "Late Cancel" : "Cancel",
                    style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 13),
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Edit", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.txt)),
                    SizedBox(width: 3),
                    Icon(LucideIcons.chevronDown, size: 13, color: AppColors.mute),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastVisitCard extends StatelessWidget {
  const _PastVisitCard({required this.booking, required this.trainer});

  final Booking booking;
  final Trainer? trainer;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final matches = kAttendanceOptions.where((o) => o.key == b.attendanceStatus);
    final opt = matches.isNotEmpty ? matches.first : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${sessionTypeLabel(b.sessionType)} · ${disciplineLabel(b.discipline)}",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(trainer?.name ?? "Removed", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  const SizedBox(height: 3),
                  Text(
                    "${dayLabel(b.date)} · ${fmtSlot(b.slot)}",
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: opt?.color ?? AppColors.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                opt?.label ?? "Unmarked",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: opt?.color ?? AppColors.mute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

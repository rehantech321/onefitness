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
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "booking_cancel_screen.dart";

/// Mirrors DayDetail.jsx — what a tapped Workout Calendar date "is": either
/// the logged workout that happened that day, the booking scheduled for it
/// (with Reschedule/Cancel for a not-yet-past one), or nothing at all.
/// Reached only for a date that has a dot (see calendarDayStatus) — anywhere
/// else routes straight into the booking flow instead (see client_shell.dart
/// pickCalendarDate).
class DayDetailScreen extends ConsumerStatefulWidget {
  const DayDetailScreen({
    super.key,
    required this.date,
    required this.onBack,
    required this.onReschedule,
    required this.onGoPlans,
  });

  final String date;
  final VoidCallback onBack;
  final ValueChanged<Booking> onReschedule;
  final VoidCallback onGoPlans;

  @override
  ConsumerState<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends ConsumerState<DayDetailScreen> {
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
      widget.onBack();
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
    final settings = ref.watch(platformSettingsProvider);
    bool canRescheduleNow(Booking b) => canReschedule(
          b,
          blockRescheduleInWindow: settings.blockRescheduleInWindow,
          lateCancellationHours: settings.lateCancellationHours,
        );

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

    final client = ref.watch(clientRecordProvider);
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final isPast = widget.date.compareTo(isoToday()) < 0;

    final logs = client.workoutLogs.where((l) => l.date == widget.date).toList();
    final log = logs.isNotEmpty ? logs.first : null;
    final dayBookings = bookings.where((b) => b.clientId == info.id && b.date == widget.date).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: widget.onBack,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.chevronLeft, size: 15),
            label: const Text("Dashboard", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 10),
          Text(dayLabel(widget.date), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (log != null) ...[
            const SectionLabel("Your workout that day"),
            if (log.dayTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Text(log.dayTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            AppCard(
              child: Column(
                children: log.exercises.map((ex) {
                  final doneSets = ex.sets.where((s) => s.completed).toList();
                  final summary = doneSets.isEmpty
                      ? "logged"
                      : doneSets.map((s) => "${s.completedReps ?? 0}×${s.completedWeight != null ? "${s.completedWeight} lb" : "BW"}").join(", ");
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (doneSets.isNotEmpty) ...[
                              const Icon(LucideIcons.check, size: 13, color: AppColors.gold),
                              const SizedBox(width: 6),
                            ],
                            Text(ex.name, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        Text(summary, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (log.coachComment != null && log.coachComment!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.goldDim),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("COACH'S NOTE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gold, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(log.coachComment!, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
          ] else if (dayBookings.isNotEmpty) ...[
            ...dayBookings.map((b) {
              final matches = trainers.where((t) => t.id == b.trainerId);
              final trainer = matches.isNotEmpty ? matches.first : null;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.calendarCheck, size: 17, color: AppColors.gold),
                        const SizedBox(width: 10),
                        Text(fmtSlot(b.slot), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${trainer?.name ?? "Coach"} · ${disciplineLabel(b.discipline)}",
                      style: const TextStyle(fontSize: 13, color: AppColors.mute),
                    ),
                    if (b.locationName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(LucideIcons.mapPin, size: 12, color: AppColors.gold),
                          const SizedBox(width: 4),
                          Text(b.locationName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gold)),
                        ],
                      ),
                    ],
                    if (isPast) ...[
                      const SizedBox(height: 12),
                      const Text(
                        "This session wasn't logged.",
                        style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic),
                      ),
                    ] else ...[
                      InkWell(
                        onTap: widget.onGoPlans,
                        child: Container(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.only(top: 12),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "YOUR ASSIGNED WORKOUT",
                                      style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      client.savedPrograms.isEmpty ? "No program assigned yet" : "View full plan",
                                      style: const TextStyle(fontSize: 13, color: AppColors.txt),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          children: [
                            if (canRescheduleNow(b))
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => widget.onReschedule(b),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: AppColors.gold.withValues(alpha: 0.12),
                                    side: const BorderSide(color: AppColors.goldDim),
                                    foregroundColor: AppColors.gold,
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                  ),
                                  child: const Text("Reschedule", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            if (canRescheduleNow(b)) const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _cancelTarget = b),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.line),
                                  foregroundColor: const Color(0xFFC97F7F),
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                ),
                                child: const Text("Cancel", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ] else
            const HintBox(text: "Nothing booked or logged this day."),
        ],
      ),
    );
  }
}

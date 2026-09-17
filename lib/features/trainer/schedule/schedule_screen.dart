import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../shell/trainer_shell_state.dart";
import "add_manual_booking_sheet.dart";
import "create_session_sheet.dart";
import "day_view.dart";
import "month_calendar.dart";

/// Mirrors ScheduleTab.jsx — a single screen switching between a month grid
/// and a drilled-in day view.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _selectedDate;

  void _openClient(String clientId) {
    ref.read(selectedClientIdProvider.notifier).select(clientId);
    ref.read(trainerModeProvider.notifier).go("clients");
  }

  // Tapping a date always opens the day view listing every session on it,
  // each as a tappable tile into its detail sheet. It used to jump straight
  // to the detail sheet when the day held a single session, which skipped
  // the day's overview and left no way to see the day as a whole.
  void _handleSelectDay(String date, Map<String, List<Booking>> bookingsByDate) {
    setState(() => _selectedDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final bookings = ref.watch(allBookingsProvider).where((b) => isOwner || b.trainerId == trainerAuth).toList();
    final relevantTrainers = ref.watch(trainersProvider).where((t) => isOwner || t.id == trainerAuth).toList();
    final blocked = ref.watch(blockedTimesProvider).where((b) => isOwner || b.trainerId == trainerAuth).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Row(
            children: [
              // Create = publish a bookable session for a coach (no client
              // yet). Book = put a specific client into a session.
              if (isOwner) ...[
                Expanded(
                  child: BtnGhost(
                    full: true,
                    onPressed: () => showCreateSessionSheet(context, ref, initialDate: _selectedDate ?? isoToday()),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(LucideIcons.plus, size: 15), SizedBox(width: 6), Text("Create session")],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: BtnGold(
                  full: true,
                  onPressed: () => showAddManualBookingSheet(context, ref, initialDate: _selectedDate ?? isoToday()),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(LucideIcons.plus, size: 15, color: Colors.white), SizedBox(width: 6), Text("Book session")],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LocalBackScope(
            isOpen: _selectedDate != null,
            onBack: () => setState(() => _selectedDate = null),
            child: _selectedDate == null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: MonthCalendar(
                      month: _month,
                      slotsByDate: _slotsByDate(bookings, relevantTrainers),
                      blockedDates: blocked.map((b) => b.date).toSet(),
                      onSelectDay: (d) => _handleSelectDay(d, _bookingsByDate(bookings)),
                      onChangeMonth: (dir) => setState(() => _month = DateTime(_month.year, _month.month + dir, 1)),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                        child: TextButton.icon(
                          onPressed: () => setState(() => _selectedDate = null),
                          icon: const Icon(LucideIcons.chevronLeft, size: 15, color: AppColors.mute),
                          label: const Text("Month", style: TextStyle(color: AppColors.mute, fontSize: 12)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        ),
                      ),
                      Expanded(child: DayView(date: _selectedDate!, onOpenClient: _openClient)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Map<String, List<Booking>> _bookingsByDate(List<Booking> bookings) {
    final map = <String, List<Booking>>{};
    for (final b in bookings) {
      (map[b.date] ??= []).add(b);
    }
    return map;
  }

  /// Times to print under each calendar date: booked sessions plus any
  /// created-but-unbooked ones, so a session the owner just published shows
  /// on the month view before anyone books it.
  Map<String, List<int>> _slotsByDate(List<Booking> bookings, List<Trainer> trainers) {
    final byDate = _bookingsByDate(bookings);
    final out = <String, Set<int>>{
      for (final entry in byDate.entries) entry.key: entry.value.map((b) => b.slot).toSet(),
    };
    for (final t in trainers) {
      for (final block in t.availability) {
        block.dates.forEach((date, slots) => out.putIfAbsent(date, () => {}).addAll(slots));
      }
    }
    return {for (final e in out.entries) e.key: (e.value.toList()..sort())};
  }
}

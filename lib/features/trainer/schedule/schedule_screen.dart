import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/trainer_providers.dart";
import "../shell/trainer_shell_state.dart";
import "add_manual_booking_sheet.dart";
import "day_view.dart";
import "month_calendar.dart";
import "session_detail_sheet.dart";

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

  // A date with exactly one trainer+slot session group opens straight to
  // its detail sheet — nothing to disambiguate. Anything else (multiple
  // sessions, or none at all — e.g. to book on an empty day) still drills
  // into the day view, same as before.
  void _handleSelectDay(String date, Map<String, List<Booking>> bookingsByDate) {
    final dayBookings = bookingsByDate[date] ?? const <Booking>[];
    final groups = dayBookings.map((b) => "${b.trainerId}|${b.slot}").toSet();
    if (groups.length == 1) {
      final b = dayBookings.first;
      showSessionDetailSheet(context, ref, trainerId: b.trainerId, date: date, slot: b.slot, onOpenClient: _openClient);
      return;
    }
    setState(() => _selectedDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final bookings = ref.watch(allBookingsProvider).where((b) => isOwner || b.trainerId == trainerAuth).toList();
    final blocked = ref.watch(blockedTimesProvider).where((b) => isOwner || b.trainerId == trainerAuth).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
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
        Expanded(
          child: LocalBackScope(
            isOpen: _selectedDate != null,
            onBack: () => setState(() => _selectedDate = null),
            child: _selectedDate == null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: MonthCalendar(
                      month: _month,
                      slotsByDate: _slotsByDate(bookings),
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

  Map<String, List<int>> _slotsByDate(List<Booking> bookings) {
    final byDate = _bookingsByDate(bookings);
    return {
      for (final entry in byDate.entries) entry.key: (entry.value.map((b) => b.slot).toSet().toList()..sort()),
    };
  }
}

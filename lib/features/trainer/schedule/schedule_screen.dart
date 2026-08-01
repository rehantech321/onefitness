import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";
import "../shell/trainer_shell_state.dart";
import "add_manual_booking_sheet.dart";
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
          child: _selectedDate == null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: MonthCalendar(
                    month: _month,
                    densityByDate: _densityByDate(bookings),
                    blockedDates: blocked.map((b) => b.date).toSet(),
                    onSelectDay: (d) => setState(() => _selectedDate = d),
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
      ],
    );
  }

  Map<String, int> _densityByDate(List bookings) {
    final map = <String, int>{};
    for (final b in bookings) {
      map[b.date] = (map[b.date] ?? 0) + 1;
    }
    return map;
  }
}

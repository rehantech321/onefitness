import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";

const _monthNames = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
const _dowLabels = ["S", "M", "T", "W", "T", "F", "S"];

/// Mirrors MonthCalendar.jsx's month grid, extended with a per-day session
/// time readout — a coach can see when their day's sessions start without
/// having to tap in, and tapping still opens (see ScheduleScreen) straight
/// to that session's detail sheet when the day only has one.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.slotsByDate,
    required this.blockedDates,
    required this.onSelectDay,
    required this.onChangeMonth,
  });

  final DateTime month;

  /// Distinct, sorted start-minute slots booked on each date — used purely
  /// for the compact time readout under the date number. Tap-target
  /// decisions (open detail directly vs. drill into the day) live in
  /// ScheduleScreen, which has the real Booking objects.
  final Map<String, List<int>> slotsByDate;
  final Set<String> blockedDates;
  final ValueChanged<String> onSelectDay;
  final void Function(int direction) onChangeMonth;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = isoToday();
    final cells = <Widget>[];
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = isoDate(DateTime(month.year, month.month, d));
      final slots = slotsByDate[date] ?? const <int>[];
      final blocked = blockedDates.contains(date);
      final isToday = date == today;
      final shown = slots.take(2).toList();
      final overflow = slots.length - shown.length;
      cells.add(InkWell(
        onTap: () => onSelectDay(date),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: isToday ? Border.all(color: AppColors.gold) : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("$d", style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: isToday ? AppColors.gold : AppColors.txt)),
                  const SizedBox(height: 2),
                  for (final s in shown)
                    Text(fmtSlotCompactAmPm(s), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.gold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (overflow > 0) Text("+$overflow", style: const TextStyle(fontSize: 9, color: AppColors.mute)),
                ],
              ),
              if (blocked) const Positioned(top: 0, right: 2, child: Icon(LucideIcons.lock, size: 8, color: AppColors.mute)),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(onPressed: () => onChangeMonth(-1), icon: const Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.mute)),
            Text("${_monthNames[month.month - 1]} ${month.year}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            IconButton(onPressed: () => onChangeMonth(1), icon: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.mute)),
          ],
        ),
        Row(children: _dowLabels.map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(fontSize: 11, color: AppColors.mute))))).toList()),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.72,
          children: cells,
        ),
      ],
    );
  }
}

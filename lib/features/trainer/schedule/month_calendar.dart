import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";

const _monthNames = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
const _dowLabels = ["S", "M", "T", "W", "T", "F", "S"];

/// Mirrors MonthCalendar.jsx — a simple month grid with a session-density
/// dot row and a small marker for blocked days.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month, // first-of-month DateTime
    required this.densityByDate,
    required this.blockedDates,
    required this.onSelectDay,
    required this.onChangeMonth,
  });

  final DateTime month;
  final Map<String, int> densityByDate;
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
      final density = (densityByDate[date] ?? 0).clamp(0, 4);
      final blocked = blockedDates.contains(date);
      final isToday = date == today;
      cells.add(InkWell(
        onTap: () => onSelectDay(date),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: isToday ? Border.all(color: AppColors.gold) : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$d", style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: isToday ? AppColors.gold : AppColors.txt)),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...List.generate(density, (_) => Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 0.5), decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle))),
                    if (blocked) Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 0.5), decoration: const BoxDecoration(color: AppColors.mute, shape: BoxShape.circle)),
                  ],
                ),
              ),
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
          children: cells,
        ),
      ],
    );
  }
}

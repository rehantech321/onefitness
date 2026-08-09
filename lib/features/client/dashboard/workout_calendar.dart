import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/client_record.dart";

/// Mirrors ClientDashboard.jsx `WorkoutCalendar` — a collapsible month grid
/// with dots marking done/missed/upcoming days, tapping a day routes out via
/// [onPickDate].
class WorkoutCalendar extends StatefulWidget {
  const WorkoutCalendar({
    super.key,
    required this.client,
    required this.info,
    required this.bookings,
    required this.onPickDate,
  });

  final ClientRecord client;
  final ClientInfo info;
  final List<Booking> bookings;
  final ValueChanged<String> onPickDate;

  @override
  State<WorkoutCalendar> createState() => _WorkoutCalendarState();
}

class _WorkoutCalendarState extends State<WorkoutCalendar> {
  bool _open = true;
  late DateTime _view = DateTime(DateTime.now().year, DateTime.now().month, 1);

  String _iso(int day) => isoDate(DateTime(_view.year, _view.month, day));

  CalendarDayStatus? _statusFor(int day) => calendarDayStatus(widget.client, widget.info, widget.bookings, _iso(day));

  Color _dotColor(CalendarDayStatus s) => switch (s) {
        CalendarDayStatus.done => AppColors.calendarDone,
        CalendarDayStatus.missed => AppColors.calendarMissed,
        CalendarDayStatus.upcoming => AppColors.calendarUpcoming,
      };

  void _shift(int n) => setState(() => _view = DateTime(_view.year, _view.month + n, 1));

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_view.year, _view.month + 1, 0).day;
    final startDay = _view.weekday % 7; // Sunday-first, matching JS getDay()
    final monthName = "${_monthNames[_view.month - 1]} ${_view.year}";
    final todayStr = isoToday();

    final counts = {CalendarDayStatus.done: 0, CalendarDayStatus.missed: 0, CalendarDayStatus.upcoming: 0};
    for (var d = 1; d <= daysInMonth; d++) {
      final s = _statusFor(d);
      if (s != null) counts[s] = counts[s]! + 1;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                const Icon(LucideIcons.calendar, size: 16, color: AppColors.gold),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text("Workout Calendar", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                if (!_open) ...[
                  _CountBadge(color: AppColors.calendarDone, value: counts[CalendarDayStatus.done]!),
                  const SizedBox(width: 10),
                  _CountBadge(color: AppColors.calendarMissed, value: counts[CalendarDayStatus.missed]!),
                  const SizedBox(width: 10),
                  _CountBadge(color: AppColors.calendarUpcoming, value: counts[CalendarDayStatus.upcoming]!),
                  const SizedBox(width: 10),
                ],
                Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: AppColors.mute),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.mute),
                  visualDensity: VisualDensity.compact,
                ),
                Text(monthName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.mute),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const ["S", "M", "T", "W", "T", "F", "S"]
                  .map((d) => Center(
                        child: Text(d, style: const TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700)),
                      ))
                  .toList(),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
              itemCount: startDay + daysInMonth,
              itemBuilder: (context, i) {
                final day = i - startDay + 1;
                if (day < 1) return const SizedBox.shrink();
                final status = _statusFor(day);
                final dateStr = _iso(day);
                final isToday = dateStr == todayStr;
                return InkWell(
                  onTap: () => widget.onPickDate(dateStr),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.gold.withValues(alpha: 0.1) : Colors.transparent,
                      border: isToday ? Border.all(color: AppColors.goldDim) : null,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "$day",
                          style: TextStyle(
                            fontSize: 12,
                            color: isToday ? AppColors.gold : AppColors.txt,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: status != null ? _dotColor(status) : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: AppColors.calendarDone, label: "Completed"),
                const SizedBox(width: 14),
                _Legend(color: AppColors.calendarMissed, label: "Missed"),
                const SizedBox(width: 14),
                _Legend(color: AppColors.calendarUpcoming, label: "Upcoming"),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _monthNames = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.color, required this.value});
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Text("$value", style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12));
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
      ],
    );
  }
}

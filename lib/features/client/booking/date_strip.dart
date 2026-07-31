import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";

const _weekdayShort = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

/// Mirrors DateStrip.jsx — a 7-day horizontal week strip with paging
/// arrows; `disablePast` blocks selecting/paging before today.
class DateStrip extends StatefulWidget {
  const DateStrip({super.key, required this.date, required this.onSelect, this.disablePast = false});

  final String date;
  final ValueChanged<String> onSelect;
  final bool disablePast;

  @override
  State<DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<DateStrip> {
  late String _weekStart = startOfWeek(widget.date);

  @override
  void didUpdateWidget(covariant DateStrip old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) {
      final idx = DateTime.parse(widget.date).difference(DateTime.parse(_weekStart)).inDays;
      if (idx < 0 || idx > 6) setState(() => _weekStart = startOfWeek(widget.date));
    }
  }

  void _page(int dir) {
    final atStart = widget.disablePast && _weekStart.compareTo(startOfWeek(isoToday())) <= 0;
    if (dir < 0 && atStart) return;
    setState(() => _weekStart = addDaysIso(_weekStart, dir * 7));
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = isoToday();
    final days = List.generate(7, (i) => addDaysIso(_weekStart, i));
    final atStart = widget.disablePast && _weekStart.compareTo(startOfWeek(todayStr)) <= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Text(dayLabel(widget.date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (widget.date == todayStr)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text("Today", style: TextStyle(fontSize: 11, color: AppColors.gold)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NavButton(icon: LucideIcons.chevronLeft, disabled: atStart, onTap: () => _page(-1)),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: days.map((d) {
                    final sel = d == widget.date;
                    final isToday = d == todayStr;
                    final past = widget.disablePast && d.compareTo(todayStr) < 0;
                    final dt = DateTime.parse(d);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: past ? null : () => widget.onSelect(d),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.gold : (isToday ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card),
                              border: Border.all(color: sel ? AppColors.gold : AppColors.line),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Opacity(
                              opacity: past ? 0.6 : 1,
                              child: Column(
                                children: [
                                  Text(
                                    _weekdayShort[dt.weekday % 7],
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: sel ? Colors.white : (past ? const Color(0xFF454545) : (isToday ? AppColors.gold : AppColors.txt)),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "${dt.day}",
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: sel ? Colors.white : (past ? const Color(0xFF454545) : (isToday ? AppColors.gold : AppColors.txt)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 4),
              _NavButton(icon: LucideIcons.chevronRight, disabled: false, onTap: () => _page(1)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.disabled, required this.onTap});
  final IconData icon;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: disabled ? const Color(0xFF333333) : AppColors.txt),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors HabitTrackerPage.jsx's stat tile — shared between the client's
/// own Habit Tracker and the coach's read-only view of it.
class HabitStatBox extends StatelessWidget {
  const HabitStatBox({super.key, required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Mirrors HabitTrackerPage.jsx's Today/Yesterday pill toggle.
class HabitDateTabButton extends StatelessWidget {
  const HabitDateTabButton({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? AppColors.gold : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute)),
        ),
      ),
    );
  }
}

/// Mirrors HabitTrackerPage.jsx's 1-10 Energy/Motivation rating row.
/// [disabled] mirrors the web's `disabled={isCoach}` — a coach sees the
/// client's own submitted value but can't change it.
class HabitRatingRow extends StatelessWidget {
  const HabitRatingRow({super.key, required this.label, required this.value, required this.onChange, this.disabled = false});
  final String label;
  final int? value;
  final ValueChanged<int> onChange;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(10, (i) {
            final n = i + 1;
            final selected = value == n;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 9 ? 5 : 0),
                child: InkWell(
                  onTap: disabled ? null : () => onChange(n),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.2) : AppColors.bg,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text("$n", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute)),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

const _habitWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const _habitMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/// Mirrors lib/format.js `niceDate` for a habit-log date heading —
/// "Wed, Aug 20".
String niceHabitDate(String iso) {
  final d = DateTime.parse(iso);
  return "${_habitWeekdays[d.weekday % 7]}, ${_habitMonths[d.month - 1]} ${d.day}";
}

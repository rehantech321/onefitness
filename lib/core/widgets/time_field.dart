import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../utils/date_utils.dart";

/// Opens the platform time picker in 12-hour AM/PM form and returns the
/// picked time as minutes from midnight, or null if dismissed.
///
/// The picker normally follows the device's 24-hour setting, which is what
/// produced "14:00" on some phones. Staff here work in AM/PM (the schedule,
/// the day view and every booking card already print it that way), so the
/// picker is pinned to match rather than left to the OS.
Future<int?> pickTime12h(BuildContext context, {required int initialMinutes}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
      child: child ?? const SizedBox.shrink(),
    ),
  );
  if (picked == null) return null;
  return picked.hour * 60 + picked.minute;
}

/// A tappable field showing a time as "9:00 AM", opening [pickTime12h].
/// [minutes] null shows the placeholder — used for an optional end time.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.placeholder = "Select time",
    this.initialWhenEmpty = 9 * 60,
    this.onClear,
  });

  final int? minutes;
  final ValueChanged<int> onChanged;
  final String placeholder;

  /// Where the picker opens when no time is set yet.
  final int initialWhenEmpty;

  /// When given, a small × appears once a time is set.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final m = minutes;
    return InkWell(
      onTap: () async {
        final picked = await pickTime12h(context, initialMinutes: m ?? initialWhenEmpty);
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m == null ? placeholder : fmtSlot(m),
                style: TextStyle(fontSize: 14, color: m == null ? AppColors.mute : AppColors.txt),
              ),
            ),
            if (m != null && onClear != null)
              InkWell(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: AppColors.mute),
              ),
          ],
        ),
      ),
    );
  }
}

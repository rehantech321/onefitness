import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../data/models/report_range.dart";

const _presets = [
  ("today", "Today"),
  ("week", "This Week"),
  ("month", "This Month"),
  ("quarter", "This Quarter"),
  ("year", "This Year"),
  ("custom", "Custom"),
];

/// Mirrors DateRangeFilter.jsx — preset pills shared by every report and by
/// My Pay, including the "Custom" pill that reveals a start/end date picker.
class DateRangeFilter extends StatefulWidget {
  const DateRangeFilter({super.key, required this.range, required this.onChange});

  final ReportRange range;
  final ValueChanged<ReportRange> onChange;

  @override
  State<DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends State<DateRangeFilter> {
  Future<void> _pickCustomDate({required bool isStart}) async {
    final range = widget.range;
    final initial = DateTime.parse(isStart ? range.start : range.end);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    final pickedIso = isoDate(picked);
    widget.onChange(
      presetRange(
        "custom",
        customStart: isStart ? pickedIso : range.start,
        customEnd: isStart ? range.end : pickedIso,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = widget.range.preset == "custom";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _presets.map((p) {
              final selected = widget.range.preset == p.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => widget.onChange(p.$1 == "custom" ? presetRange("custom", customStart: widget.range.start, customEnd: widget.range.end) : presetRange(p.$1)),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(p.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.gold : AppColors.mute)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (isCustom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _CustomDateField(label: "Start", date: widget.range.start, onTap: () => _pickCustomDate(isStart: true))),
              const SizedBox(width: 8),
              Expanded(child: _CustomDateField(label: "End", date: widget.range.end, onTap: () => _pickCustomDate(isStart: false))),
            ],
          ),
        ],
      ],
    );
  }
}

class _CustomDateField extends StatelessWidget {
  const _CustomDateField({required this.label, required this.date, required this.onTap});
  final String label;
  final String date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Text("$label: ", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
            Expanded(child: Text(date, style: const TextStyle(fontSize: 12, color: AppColors.txt, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

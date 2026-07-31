import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../data/models/report_range.dart";

const _presets = [("today", "Today"), ("week", "This Week"), ("month", "This Month"), ("quarter", "This Quarter"), ("year", "This Year")];

/// Mirrors DateRangeFilter.jsx — preset pills shared by every report and by
/// My Pay. No custom start/end picker in this trimmed build (presets cover
/// the common cases).
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({super.key, required this.range, required this.onChange});

  final ReportRange range;
  final ValueChanged<ReportRange> onChange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _presets.map((p) {
          final selected = range.preset == p.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onChange(presetRange(p.$1)),
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
    );
  }
}

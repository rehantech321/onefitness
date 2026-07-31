import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "exercise_lifts_tab.dart";
import "measurements_tab.dart";
import "progress_photos_tab.dart";

const _ranges = [(30, "30d"), (90, "90d"), (365, "1yr"), (0, "All")];

/// Mirrors LogProgressPage.jsx — Body/Lifts/Photos tab switcher plus a
/// shared date-range picker (hidden on the Photos tab).
class LogProgressScreen extends StatefulWidget {
  const LogProgressScreen({super.key});

  @override
  State<LogProgressScreen> createState() => _LogProgressScreenState();
}

class _LogProgressScreenState extends State<LogProgressScreen> {
  String _tab = "measurements";
  int _range = 90;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              _TabButton(label: "Body", selected: _tab == "measurements", onTap: () => setState(() => _tab = "measurements")),
              _TabButton(label: "Lifts", selected: _tab == "exercises", onTap: () => setState(() => _tab = "exercises")),
              _TabButton(label: "Photos", selected: _tab == "photos", onTap: () => setState(() => _tab = "photos")),
            ],
          ),
        ),
        if (_tab != "photos")
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Row(
              children: _ranges
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setState(() => _range = r.$1),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: _range == r.$1 ? AppColors.gold.withValues(alpha: 0.12) : Colors.transparent,
                              border: Border.all(color: _range == r.$1 ? AppColors.gold : AppColors.line),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              r.$2,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _range == r.$1 ? AppColors.gold : AppColors.mute),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        Expanded(
          child: switch (_tab) {
            "exercises" => const ExerciseLiftsTab(),
            "photos" => const ProgressPhotosTab(),
            _ => MeasurementsTab(rangeDays: _range),
          },
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute),
          ),
        ),
      ),
    );
  }
}

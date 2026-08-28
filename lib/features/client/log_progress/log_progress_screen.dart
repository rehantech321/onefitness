import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "exercise_lifts_tab.dart";
import "measurements_tab.dart";
import "progress_photos_tab.dart";

const _ranges = [(30, "30d"), (90, "90d"), (365, "1yr"), (0, "All")];

/// Mirrors LogProgressPage.jsx — Body/Lifts/Photos tab switcher. Swipeable
/// via SwipeableTabView — see client_shell.dart's `_swipeOwnedByScreen` for
/// why the shell's own swipe-to-go-back gesture steps aside on this screen.
class LogProgressScreen extends StatefulWidget {
  const LogProgressScreen({super.key});

  @override
  State<LogProgressScreen> createState() => _LogProgressScreenState();
}

class _LogProgressScreenState extends State<LogProgressScreen> {
  int _range = 90;

  @override
  Widget build(BuildContext context) {
    return SwipeableTabView(
      labels: const ["Body", "Lifts", "Photos"],
      children: [
        Column(
          children: [
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
            Expanded(child: MeasurementsTab(rangeDays: _range)),
          ],
        ),
        const ExerciseLiftsTab(),
        const ProgressPhotosTab(),
      ],
    );
  }
}

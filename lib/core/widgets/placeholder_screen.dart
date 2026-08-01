import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";

/// Stand-in for screens not yet ported from the web app — makes navigation
/// fully clickable while each feature is built out in its own pass.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.hammer, size: 28, color: AppColors.goldDim),
            const SizedBox(height: 12),
            Text(
              "$title — coming in a later pass",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.mute, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `BackBar` — chevron + "Back" + optional title.
class BackBar extends StatelessWidget {
  const BackBar({super.key, required this.onBack, this.title});

  /// Null disables the button rather than hiding it, so a screen that is
  /// mid-way through something irreversible — creating an account, say —
  /// can stop someone leaving without the row jumping around as it
  /// appears and disappears.
  final VoidCallback? onBack;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.chevron_left, size: 16),
            label: const Text("Back", style: TextStyle(fontSize: 13)),
          ),
          if (title != null) ...[
            const SizedBox(width: 8),
            Text(title!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.txt)),
          ],
        ],
      ),
    );
  }
}

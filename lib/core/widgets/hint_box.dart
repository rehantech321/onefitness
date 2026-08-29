import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `Hint` — muted informational card.
class HintBox extends StatelessWidget {
  const HintBox({super.key, required this.text, this.bordered = true});

  final String text;

  /// Set false for a plain, borderless hint — same text/color, no card
  /// chrome. Defaults true so every existing call site is unaffected.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: bordered ? Border.all(color: AppColors.line) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.mute, fontSize: 13, height: 1.6),
      ),
    );
  }
}

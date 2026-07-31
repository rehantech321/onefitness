import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `Tag` — small pill badge, gold or neutral.
class Tag extends StatelessWidget {
  const Tag({super.key, required this.text, this.gold = false});

  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: gold ? AppColors.gold.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: gold ? AppColors.goldDim : AppColors.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: gold ? AppColors.gold : AppColors.mute,
        ),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "pressable_scale.dart";

/// Mirrors the web app's `card()` style helper (lib/helpers.js):
/// CARD background, LINE border, 12px radius, 14px padding, 12px bottom margin.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.borderColor,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final Color? borderColor;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: borderColor ?? AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}

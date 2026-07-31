import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `BtnGold` — solid gold pill button.
class BtnGold extends StatelessWidget {
  const BtnGold({super.key, required this.onPressed, required this.child, this.full = false});

  final VoidCallback? onPressed;
  final Widget child;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.5),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      child: child,
    );
    return full ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Mirrors FormPrimitives.jsx `BtnGhost` — outlined muted button.
class BtnGhost extends StatelessWidget {
  const BtnGhost({super.key, required this.onPressed, required this.child, this.full = false});

  final VoidCallback? onPressed;
  final Widget child;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.mute,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      child: child,
    );
    return full ? SizedBox(width: double.infinity, child: button) : button;
  }
}

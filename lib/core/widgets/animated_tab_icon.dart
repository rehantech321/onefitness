import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Icon + label pair for a bottom nav tab, with color and a gentle scale pop
/// animated in on selection — shared by ClientShell and TrainerShell so both
/// bottom bars feel identical.
class AnimatedTabIcon extends StatelessWidget {
  const AnimatedTabIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.size = 21,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold : AppColors.mute;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1.12 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: const Duration(milliseconds: 200),
            builder: (context, c, _) => Icon(icon, size: size, color: c),
          ),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}

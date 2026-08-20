import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../data/models/merit_badge_def.dart";
import "../theme/app_colors.dart";

/// Mirrors SubBadgeIcon.jsx — the one place any Gym Citizen / Progress
/// Tracker sub-badge's artwork ever renders. Real art exists for all 13
/// known sub-badges (kSubBadgeImagePaths); the icon fallback below only
/// matters for a hypothetical future sub-badge added without art yet.
class SubBadgeIcon extends StatelessWidget {
  const SubBadgeIcon({super.key, required this.subBadgeKey, this.size = 44, this.earned = false});

  final String subBadgeKey;
  final double size;
  final bool earned;

  static const _fallbackIcons = {
    "gym_citizen_rerack": LucideIcons.packageCheck,
    "gym_citizen_setup": LucideIcons.wrench,
    "gym_citizen_reset": LucideIcons.refreshCw,
    "gym_citizen_loadup": LucideIcons.dumbbell,
    "gym_citizen_knowit": LucideIcons.bookOpenCheck,
    "gym_citizen_countreps": LucideIcons.hash,
    "gym_citizen_coachable": LucideIcons.ear,
    "gym_citizen_gymaware": LucideIcons.eye,
    "gym_citizen_workoutready": LucideIcons.checkCircle2,
    "gym_citizen_gymcourtesy": LucideIcons.heartHandshake,
    "progress_tracker_photo": LucideIcons.camera,
    "progress_tracker_measurements": LucideIcons.ruler,
    "progress_tracker_workout": LucideIcons.dumbbell,
  };

  @override
  Widget build(BuildContext context) {
    final borderColor = earned ? AppColors.goldDim : AppColors.line;
    final path = kSubBadgeImagePaths[subBadgeKey];
    if (path != null) {
      final image = ClipOval(
        child: Image.asset(path, width: size, height: size, fit: BoxFit.cover),
      );
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borderColor, width: 1.5)),
        child: earned
            ? image
            : ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: Opacity(opacity: 0.6, child: image),
              ),
      );
    }
    final icon = _fallbackIcons[subBadgeKey];
    if (icon == null) return SizedBox(width: size, height: size);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned ? const Color(0x1F33733F) : Colors.transparent,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Icon(icon, size: size * 0.5, color: earned ? AppColors.gold : AppColors.mute),
    );
  }
}

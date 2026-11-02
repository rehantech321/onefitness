import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../data/providers/theme_mode_provider.dart";
import "../theme/app_colors.dart";
import "section_label.dart";

/// Light / Dark / Match phone.
///
/// One widget for both sides of the app — the client's Profile & Settings
/// and a coach's My Profile — so the choice reads and behaves identically
/// whichever account you're in.
///
/// The setting lives on the device, not the account: someone signed in on a
/// bright gym floor and a dark bedroom wants different answers in each
/// place, and a shared tablet shouldn't carry one coach's choice over to
/// the next person.
class ThemeModePicker extends ConsumerWidget {
  const ThemeModePicker({super.key, this.showLabel = true});

  final bool showLabel;

  static const _options = [
    (ThemeMode.light, "Light", LucideIcons.sun),
    (ThemeMode.dark, "Dark", LucideIcons.moon),
    (ThemeMode.system, "Match phone", LucideIcons.smartphone),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const SectionLabel("Appearance"),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            for (final (value, label, icon) in _options) ...[
              Expanded(
                child: _Option(
                  label: label,
                  icon: icon,
                  selected: mode == value,
                  onTap: () => ref.read(themeModeProvider.notifier).set(value),
                ),
              ),
              if (value != ThemeMode.system) const SizedBox(width: 8),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            mode == ThemeMode.system
                ? "Follows your phone's light or dark setting."
                : "Always ${themeModeLabel(mode).toLowerCase()}, whatever your phone is set to.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// The same choice as [ThemeModePicker], as one button for the menu header.
///
/// The full picker lives in Profile Settings and a coach's My Profile, which
/// is the right home for it but not somewhere anyone goes mid-session. This
/// sits in the drawer, so switching to dark on a dim gym floor is two taps
/// from any screen instead of a trip through settings.
///
/// A menu rather than a cycling button: tapping one icon through
/// light → dark → match phone gives no clue what the next tap does, and lands
/// people on "match phone" by accident when they wanted dark.
class ThemeModeToggleButton extends ConsumerWidget {
  const ThemeModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final current = ThemeModePicker._options.firstWhere((o) => o.$1 == mode);

    return PopupMenuButton<ThemeMode>(
      tooltip: "Appearance: ${themeModeLabel(mode)}",
      onSelected: (next) => ref.read(themeModeProvider.notifier).set(next),
      color: AppColors.card,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 184),
      icon: Icon(current.$3, size: 19, color: AppColors.gold),
      // Matches the 44px touch target the drawer's close button uses, so the
      // two sit level and both stay thumb-sized.
      padding: EdgeInsets.zero,
      iconSize: 19,
      itemBuilder: (context) => [
        for (final (value, label, icon) in ThemeModePicker._options)
          PopupMenuItem(
            value: value,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: value == mode ? AppColors.gold : AppColors.mute,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == mode ? FontWeight.w700 : FontWeight.w500,
                      color: value == mode ? AppColors.gold : AppColors.txt,
                    ),
                  ),
                ),
                if (value == mode)
                  Icon(LucideIcons.check, size: 15, color: AppColors.gold),
              ],
            ),
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? AppColors.gold : AppColors.mute),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.gold : AppColors.mute,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "habits_tab.dart";
import "logged_tab.dart";
import "notes_tab.dart";
import "plans_tab.dart";
import "profile_tab.dart";
import "squad_tab.dart";

class _TabDef {
  const _TabDef(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _primary = [
  _TabDef("profile", "Profile", LucideIcons.user),
  _TabDef("plans", "Plans", LucideIcons.clipboardList),
  _TabDef("logs", "Logged", LucideIcons.history),
];

const _moreTabs = [
  _TabDef("habits", "Habits", LucideIcons.flame),
  _TabDef("notes", "Notes", LucideIcons.flag),
  _TabDef("squad", "Squad", LucideIcons.users2),
];

/// Mirrors TrainerView.jsx — the per-client tab bar (3 primary tabs + a
/// "More" dropdown for Habits/Notes/Squad), all fully built.
class TrainerView extends StatefulWidget {
  const TrainerView({super.key, required this.clientId});

  final String clientId;

  @override
  State<TrainerView> createState() => _TrainerViewState();
}

class _TrainerViewState extends State<TrainerView> {
  String _tab = "profile";
  bool _moreOpen = false;

  @override
  void didUpdateWidget(covariant TrainerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) {
      setState(() {
        _tab = "profile";
        _moreOpen = false;
      });
    }
  }

  void _goTab(String k) => setState(() {
        _tab = k;
        _moreOpen = false;
      });

  @override
  Widget build(BuildContext context) {
    final activeInMore = _moreTabs.any((t) => t.key == _tab);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  ..._primary.map((t) => Expanded(child: _TabButton(def: t, active: _tab == t.key, onTap: () => _goTab(t.key)))),
                  Expanded(
                    child: _TabButton(
                      def: const _TabDef("more", "More", LucideIcons.moreHorizontal),
                      active: _moreOpen || activeInMore,
                      onTap: () => setState(() => _moreOpen = !_moreOpen),
                    ),
                  ),
                ],
              ),
            ),
            if (_moreOpen)
              Positioned(
                top: 46,
                right: 0,
                child: Container(
                  width: 190,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _moreTabs.map((t) {
                      final active = _tab == t.key;
                      return InkWell(
                        onTap: () => _goTab(t.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: active ? AppColors.gold.withValues(alpha: 0.12) : null,
                            border: const Border(bottom: BorderSide(color: AppColors.line)),
                          ),
                          child: Row(
                            children: [
                              Icon(t.icon, size: 16, color: active ? AppColors.gold : AppColors.mute),
                              const SizedBox(width: 12),
                              Text(
                                t.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: active ? AppColors.gold : AppColors.txt,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    switch (_tab) {
      case "profile":
        return ProfileTab(clientId: widget.clientId);
      case "logs":
        return LoggedTab(clientId: widget.clientId);
      case "plans":
        return PlansTab(clientId: widget.clientId);
      case "habits":
        return HabitsTab(clientId: widget.clientId);
      case "notes":
        return NotesTab(clientId: widget.clientId);
      case "squad":
        return SquadTab(clientId: widget.clientId);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.def, required this.active, required this.onTap});
  final _TabDef def;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.mute;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? AppColors.gold : Colors.transparent, width: 2))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(def.icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(def.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

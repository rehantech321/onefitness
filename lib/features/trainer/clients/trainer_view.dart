import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../data/providers/trainer_providers.dart";
import "habits_tab.dart";
import "intake_tab.dart";
import "logged_tab.dart";
import "merit_badges_tab.dart";
import "notes_tab.dart";
import "plans_tab.dart";
import "points_tab.dart";
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
  _TabDef("points", "Points", LucideIcons.gift),
  _TabDef("badges", "Badges", LucideIcons.award),
];

/// Mirrors TrainerView.jsx — the per-client tab bar (3 primary tabs + a
/// "More" dropdown for Habits/Notes/Squad), all fully built.
class TrainerView extends ConsumerStatefulWidget {
  const TrainerView({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<TrainerView> createState() => _TrainerViewState();
}

class _TrainerViewState extends ConsumerState<TrainerView> {
  String _tab = "profile";

  @override
  void initState() {
    super.initState();
    // trainerClientRecordsProvider is only ever bulk-loaded once, at sign-in
    // — nothing refreshes it afterward (no realtime subscription on
    // client_records), so a program/nutrition/etc. change made elsewhere
    // (e.g. the web app, in a separate session) after this coach signed in
    // would sit invisible for the rest of the app session. Re-fetching this
    // one client's record whenever a coach opens them (this only runs once
    // per TrainerView instance, since clients_screen.dart keys it by
    // clientId) keeps every tab here current without refetching the whole
    // roster.
    _refreshRecord();
  }

  Future<void> _refreshRecord() async {
    final baseline = ref.read(trainerClientRecordsProvider)[widget.clientId];
    try {
      final fresh = await SupabaseService.loadClientRecord(widget.clientId);
      if (!mounted) return;
      // If a note/program/etc. was added locally while this fetch was in
      // flight, the provider entry is no longer the same object we started
      // from — applying this now-stale snapshot on top would silently wipe
      // out that edit from the UI (it'd still be saved server-side, but
      // would look "gone" to the coach). Skip the refresh in that case.
      final current = ref.read(trainerClientRecordsProvider)[widget.clientId];
      if (!identical(current, baseline)) return;
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (_) => fresh);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant TrainerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) {
      setState(() => _tab = "profile");
    }
  }

  void _goTab(String k) => setState(() => _tab = k);

  // Uses showMenu (the root Overlay) rather than a Positioned-in-Stack
  // dropdown: a Positioned that overflows its Stack's own box paints
  // *behind* the next sibling in the outer Column (ProfileTab's content),
  // which silently clipped the last couple of menu items when this list
  // grew past 3 entries. showMenu always paints above everything.
  Future<void> _openMoreMenu(BuildContext buttonContext) async {
    final button = buttonContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: buttonContext,
      position: position,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.line)),
      constraints: const BoxConstraints(minWidth: 190),
      items: _moreTabs.map((t) {
        final active = _tab == t.key;
        return PopupMenuItem<String>(
          value: t.key,
          child: Row(
            children: [
              Icon(t.icon, size: 16, color: active ? AppColors.gold : AppColors.mute),
              const SizedBox(width: 12),
              Text(t.label, style: TextStyle(fontSize: 14, color: active ? AppColors.gold : AppColors.txt, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        );
      }).toList(),
    );
    if (selected != null) _goTab(selected);
  }

  @override
  Widget build(BuildContext context) {
    final activeInMore = _moreTabs.any((t) => t.key == _tab);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              ..._primary.map((t) => Expanded(child: _TabButton(def: t, active: _tab == t.key, onTap: () => _goTab(t.key)))),
              Expanded(
                child: Builder(
                  builder: (btnContext) => _TabButton(
                    def: const _TabDef("more", "More", LucideIcons.moreHorizontal),
                    active: activeInMore,
                    onTap: () => _openMoreMenu(btnContext),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    switch (_tab) {
      case "profile":
        return ProfileTab(clientId: widget.clientId, onGoToIntake: () => _goTab("intake"));
      case "intake":
        return IntakeTab(clientId: widget.clientId);
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
      case "points":
        return PointsTab(clientId: widget.clientId);
      case "badges":
        return MeritBadgesTab(clientId: widget.clientId);
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

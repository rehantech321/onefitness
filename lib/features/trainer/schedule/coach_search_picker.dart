import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer.dart";

/// Coach counterpart of ClientSearchPicker — a name search over the staff
/// list for the scheduling sheets, with a "Create coach" action beneath the
/// search for the case where the coach being scheduled isn't set up yet.
class CoachSearchPicker extends StatefulWidget {
  const CoachSearchPicker({
    super.key,
    required this.trainers,
    required this.onSelect,
    this.onCreateCoach,
    this.selectedId,
  });

  final List<Trainer> trainers;
  final ValueChanged<Trainer> onSelect;

  /// Shown under the search box when provided (owner only — coaches can't
  /// add staff).
  final VoidCallback? onCreateCoach;
  final String? selectedId;

  @override
  State<CoachSearchPicker> createState() => _CoachSearchPickerState();
}

class _CoachSearchPickerState extends State<CoachSearchPicker> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _controller.text.trim().toLowerCase();
    final visible = widget.trainers
        .where((t) => q.isEmpty || t.name.toLowerCase().contains(q) || (t.email ?? "").toLowerCase().contains(q))
        .take(20)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppField(controller: _controller, placeholder: "Search coaches…", onChanged: (_) => setState(() {})),
        if (widget.onCreateCoach != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onCreateCoach,
              style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(horizontal: 4)),
              icon: const Icon(LucideIcons.userPlus, size: 14),
              label: const Text("Create coach", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          height: 200,
          child: visible.isEmpty
              ? const HintBox(text: "No matching coaches.")
              : ListView(
                  children: visible
                      .map((t) => AppCard(
                            borderColor: t.id == widget.selectedId ? AppColors.gold : null,
                            onTap: () => widget.onSelect(t),
                            child: Row(
                              children: [
                                Avatar(name: t.name, size: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      if ((t.email ?? "").isNotEmpty)
                                        Text(t.email!, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                    ],
                                  ),
                                ),
                                if (t.id == widget.selectedId) const Icon(LucideIcons.check, size: 16, color: AppColors.gold),
                              ],
                            ),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

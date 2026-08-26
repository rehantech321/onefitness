import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/exercise_def.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ExercisesTab.jsx + ExerciseEditForm.jsx — the coach-editable
/// exercise library. Trimmed: no video field, no regression/progression
/// swap-links, no "used in these programs" delete guard (this trimmed
/// build's programs library is small enough that a plain confirm suffices).
class ExercisesScreen extends ConsumerStatefulWidget {
  const ExercisesScreen({super.key});

  @override
  ConsumerState<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends ConsumerState<ExercisesScreen> {
  final _search = TextEditingController();
  ExerciseDef? _editing;
  bool _creatingNew = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exerciseCatalogProvider);

    if (_editing != null || _creatingNew) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creatingNew = false;
        }),
        child: _ExerciseEditForm(
          initial: _editing,
          onCancel: () => setState(() {
            _editing = null;
            _creatingNew = false;
          }),
          onSave: (ex) async {
            try {
              await SupabaseService.upsertExercise(ex);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't save — check your connection and try again.",
                    ),
                  ),
                );
              }
              return;
            }
            ref.read(exerciseCatalogProvider.notifier).upsert(ex);
            setState(() {
              _editing = null;
              _creatingNew = false;
            });
          },
          onDelete: _editing == null
              ? null
              : () async {
                  final id = _editing!.id;
                  try {
                    await SupabaseService.deleteExercise(id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Couldn't delete — check your connection and try again.",
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  ref.read(exerciseCatalogProvider.notifier).remove(id);
                  setState(() => _editing = null);
                },
        ),
      );
    }

    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? catalog
        : catalog
              .where(
                (e) =>
                    e.name.toLowerCase().contains(q) ||
                    e.primaryMuscle.toLowerCase().contains(q) ||
                    e.movementPattern.toLowerCase().contains(q) ||
                    e.equipment.any((eq) => eq.toLowerCase().contains(q)),
              )
              .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel("Exercises (${catalog.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creatingNew = true),
                icon: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: const Text(
                  "New exercise",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          AppField(
            controller: _search,
            placeholder: "Search name, muscle, movement, equipment…",
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ...visible.map(
            (e) => AppCard(
              onTap: () => setState(() => _editing = e),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 5,
                          children: [
                            Tag(text: e.primaryMuscle, gold: true),
                            Tag(text: e.movementPattern),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 15,
                    color: AppColors.mute,
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            const HintBox(text: "No exercises match that search."),
        ],
      ),
    );
  }
}

class _ExerciseEditForm extends StatefulWidget {
  const _ExerciseEditForm({
    required this.initial,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
  });
  final ExerciseDef? initial;
  final VoidCallback onCancel;
  final ValueChanged<ExerciseDef> onSave;
  final VoidCallback? onDelete;

  @override
  State<_ExerciseEditForm> createState() => _ExerciseEditFormState();
}

class _ExerciseEditFormState extends State<_ExerciseEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late String _movement =
      widget.initial?.movementPattern ?? kMovementPatterns.first;
  late String _muscle = widget.initial?.primaryMuscle ?? kMuscleGroups.first;
  late final _equipment = TextEditingController(
    text: widget.initial?.equipment.join(", ") ?? "",
  );
  late final _setup = TextEditingController(text: widget.initial?.setup ?? "");
  late final _cues = TextEditingController(text: widget.initial?.cues ?? "");
  late final _coachNotes = TextEditingController(
    text: widget.initial?.coachNotes ?? "",
  );

  @override
  void dispose() {
    _name.dispose();
    _equipment.dispose();
    _setup.dispose();
    _cues.dispose();
    _coachNotes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(
            onBack: widget.onCancel,
            title: widget.initial != null ? "Edit Exercise" : "New Exercise",
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Name",
            child: AppField(controller: _name),
          ),
          const SizedBox(height: 10),
          const Text(
            "MOVEMENT PATTERN",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _ChipPicker(
            value: _movement,
            options: kMovementPatterns,
            onChanged: (v) => setState(() => _movement = v),
          ),
          const SizedBox(height: 10),
          const Text(
            "PRIMARY MUSCLE",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _ChipPicker(
            value: _muscle,
            options: kMuscleGroups,
            onChanged: (v) => setState(() => _muscle = v),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Equipment (comma-separated)",
            child: AppField(controller: _equipment),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Setup",
            child: AppField(controller: _setup),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Cues",
            child: AppField(controller: _cues),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Coach notes (internal, never shown to clients)",
            child: AppField(controller: _coachNotes),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(
                          ExerciseDef(
                            id:
                                widget.initial?.id ??
                                _name.text.trim().toLowerCase().replaceAll(
                                  RegExp(r"\s+"),
                                  "-",
                                ),
                            name: _name.text.trim(),
                            movementPattern: _movement,
                            primaryMuscle: _muscle,
                            equipment: _equipment.text
                                .split(",")
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                            setup: _setup.text.trim().isEmpty
                                ? null
                                : _setup.text.trim(),
                            cues: _cues.text.trim().isEmpty
                                ? null
                                : _cues.text.trim(),
                            coachNotes: _coachNotes.text.trim().isEmpty
                                ? null
                                : _coachNotes.text.trim(),
                          ),
                        ),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
              ),
              child: const Text("Delete exercise"),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final selected = value == o;
        return InkWell(
          onTap: () => onChanged(o),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.15)
                  : AppColors.card,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.line,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              o,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.gold : AppColors.txt,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

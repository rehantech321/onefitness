import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/exercise_prescription.dart";
import "../../../data/models/program_day.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/providers/trainer_providers.dart";
import "exercise_picker_sheet.dart";

/// Mirrors ProgramBuilder.jsx — day list + a per-day scrolling exercise
/// editor (sets/reps/weight/rest/notes, superset coupling, laterality).
/// When [clientId] is set, saving assigns the program to that client (and
/// also drops a copy in the shared library, mirroring the source's
/// SaveProgramDialog behavior); when null (drawer "Build Workout Program"),
/// saving only writes to the library.
class ProgramBuilderScreen extends ConsumerStatefulWidget {
  const ProgramBuilderScreen({super.key, this.clientId, this.existing});

  final String? clientId;
  final SavedProgram? existing;

  @override
  ConsumerState<ProgramBuilderScreen> createState() => _ProgramBuilderScreenState();
}

class _ProgramBuilderScreenState extends ConsumerState<ProgramBuilderScreen> {
  late List<ProgramDay> _days = widget.existing?.programDays.toList() ?? [];
  int? _activeDay;

  void _addDay() {
    setState(() {
      _days = [..._days, ProgramDay(id: DateTime.now().microsecondsSinceEpoch.toString(), title: "Day ${_days.length + 1}")];
      _activeDay = _days.length - 1;
    });
  }

  void _updateDay(int i, ProgramDay Function(ProgramDay) f) => setState(() => _days = [for (var j = 0; j < _days.length; j++) j == i ? f(_days[j]) : _days[j]]);

  void _removeDay(int i) => setState(() {
        _days = [..._days]..removeAt(i);
        _activeDay = null;
      });

  Future<void> _save() async {
    final name = await _promptName(context, widget.existing?.name ?? "");
    if (name == null || name.trim().isEmpty) return;
    final program = SavedProgram(id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim(), programDays: _days);
    if (widget.clientId != null) {
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId!, (r) {
        final exists = r.savedPrograms.any((p) => p.id == program.id);
        final list = exists ? r.savedPrograms.map((p) => p.id == program.id ? program : p).toList() : [...r.savedPrograms, program];
        return r.copyWith(savedPrograms: list);
      });
      ref.read(programsLibraryProvider.notifier).add(SavedProgram(id: DateTime.now().microsecondsSinceEpoch.toString(), name: program.name, programDays: _days));
    } else {
      final exists = ref.read(programsLibraryProvider).any((p) => p.id == program.id);
      if (exists) {
        ref.read(programsLibraryProvider.notifier).update(program.id, (_) => program);
      } else {
        ref.read(programsLibraryProvider.notifier).add(program);
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeDay != null && _activeDay! < _days.length) {
      return _DayExerciseEditor(
        day: _days[_activeDay!],
        onBack: () => setState(() => _activeDay = null),
        onChange: (f) => _updateDay(_activeDay!, f),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Program Days"),
              TextButton.icon(onPressed: _addDay, icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold), label: const Text("Add day", style: TextStyle(color: AppColors.gold, fontSize: 12))),
            ],
          ),
          if (_days.isEmpty) const HintBox(text: "No days yet — tap Add day to start building."),
          ..._days.asMap().entries.map((entry) {
            final i = entry.key;
            final day = entry.value;
            return AppCard(
              onTap: () => setState(() => _activeDay = i),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(day.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text("${day.exercises.length} exercise${day.exercises.length == 1 ? '' : 's'}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => _removeDay(i), icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B))),
                  const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          BtnGold(full: true, onPressed: _days.isEmpty ? null : _save, child: const Text("Save program")),
        ],
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text("Program name"),
      content: AppField(controller: controller, placeholder: "e.g. Full Body Strength"),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("Save")),
      ],
    ),
  );
}

class _DayExerciseEditor extends StatefulWidget {
  const _DayExerciseEditor({required this.day, required this.onBack, required this.onChange});
  final ProgramDay day;
  final VoidCallback onBack;
  final void Function(ProgramDay Function(ProgramDay)) onChange;

  @override
  State<_DayExerciseEditor> createState() => _DayExerciseEditorState();
}

class _DayExerciseEditorState extends State<_DayExerciseEditor> {
  late final _title = TextEditingController(text: widget.day.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _addExercise() async {
    final picked = await showExercisePickerSheet(context);
    if (picked == null) return;
    widget.onChange((d) => d.copyWith(exercises: [
          ...d.exercises,
          ExercisePrescription(id: DateTime.now().microsecondsSinceEpoch.toString(), name: picked.name, exerciseId: picked.id, group: picked.primaryMuscle),
        ]));
  }

  void _updateExercise(int i, ExercisePrescription Function(ExercisePrescription) f) {
    widget.onChange((d) => d.copyWith(exercises: [for (var j = 0; j < d.exercises.length; j++) j == i ? f(d.exercises[j]) : d.exercises[j]]));
  }

  void _removeExercise(int i) {
    widget.onChange((d) => d.copyWith(exercises: [...d.exercises]..removeAt(i)));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Day"),
          const SizedBox(height: 10),
          AppField(controller: _title, onChanged: (v) => widget.onChange((d) => ProgramDay(id: d.id, title: v, exercises: d.exercises))),
          const SizedBox(height: 14),
          ...widget.day.exercises.asMap().entries.map((entry) {
            final i = entry.key;
            final ex = entry.value;
            final coupledWithNext = ex.supersetId != null && i + 1 < widget.day.exercises.length && widget.day.exercises[i + 1].supersetId == ex.supersetId;
            return Container(
              margin: EdgeInsets.only(bottom: coupledWithNext ? 2 : 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: ex.supersetId != null ? AppColors.gold : AppColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ex.supersetId != null) const Text("SUPERSET", style: TextStyle(fontSize: 9, color: AppColors.gold, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  Row(
                    children: [
                      Expanded(child: Text(ex.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      IconButton(onPressed: () => _removeExercise(i), icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B))),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: MiniField(label: "Sets", value: "${ex.sets}", ph: "3", onChange: (v) => _updateExercise(i, (e) => e.copyWith(sets: int.tryParse(v) ?? e.sets)))),
                      const SizedBox(width: 6),
                      Expanded(child: MiniField(label: "Reps", value: "${ex.reps}", ph: "10", onChange: (v) => _updateExercise(i, (e) => e.copyWith(reps: int.tryParse(v) ?? e.reps)))),
                      const SizedBox(width: 6),
                      Expanded(child: MiniField(label: "Weight", value: ex.weight ?? "", ph: "lbs", onChange: (v) => _updateExercise(i, (e) => e.copyWith(weight: v)))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: MiniField(label: "Rest", value: ex.rest ?? "", ph: "60s", onChange: (v) => _updateExercise(i, (e) => e.copyWith(rest: v)))),
                      const SizedBox(width: 6),
                      Expanded(child: MiniField(label: "Time", value: ex.time ?? "", ph: "", onChange: (v) => _updateExercise(i, (e) => e.copyWith(time: v)))),
                      const SizedBox(width: 6),
                      Expanded(child: MiniField(label: "Distance", value: ex.distance ?? "", ph: "", onChange: (v) => _updateExercise(i, (e) => e.copyWith(distance: v)))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AppField(controller: TextEditingController(text: ex.notes ?? ""), placeholder: "Coach notes / cues…", onChanged: (v) => _updateExercise(i, (e) => e.copyWith(notes: v))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      InkWell(
                        onTap: () => _updateExercise(i, (e) => e.copyWith(laterality: e.laterality == "bilateral" ? "unilateral" : "bilateral")),
                        child: Tag(text: ex.laterality == "unilateral" ? "Unilateral" : "Bilateral", gold: ex.laterality == "unilateral"),
                      ),
                      if (i + 1 < widget.day.exercises.length)
                        InkWell(
                          onTap: () {
                            if (ex.supersetId != null) {
                              _updateExercise(i, (e) => e.copyWith(clearSupersetId: true));
                              _updateExercise(i + 1, (e) => e.copyWith(clearSupersetId: true));
                            } else {
                              final sid = DateTime.now().microsecondsSinceEpoch.toString();
                              _updateExercise(i, (e) => e.copyWith(supersetId: sid));
                              _updateExercise(i + 1, (e) => e.copyWith(supersetId: sid));
                            }
                          },
                          child: Tag(text: ex.supersetId != null ? "Remove from superset" : "Couple with next"),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
          BtnGhost(full: true, onPressed: _addExercise, child: const Text("+ Add exercise")),
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/exercise_prescription.dart";
import "../../../data/models/program_day.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "exercise_picker_sheet.dart";

String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

String _exerciseNumber(int i) => (i + 1).toString().padLeft(2, "0");

/// Mirrors ProgramBuilder.jsx — day list + a per-day scrolling exercise
/// editor (sets/reps/weight/rest/notes, superset coupling, laterality).
/// When [clientId] is set this edits that client's *live* split
/// (client_records.data.programDays), auto-saving on every change, same as
/// persist() being called on every edit on the web; when null (drawer
/// "Build Workout Program") it's a template-only builder that only writes
/// anywhere once "Save program" is used.
class ProgramBuilderScreen extends ConsumerStatefulWidget {
  const ProgramBuilderScreen({super.key, this.clientId});

  final String? clientId;

  @override
  ConsumerState<ProgramBuilderScreen> createState() =>
      _ProgramBuilderScreenState();
}

class _ProgramBuilderScreenState extends ConsumerState<ProgramBuilderScreen> {
  late List<ProgramDay> _days = widget.clientId != null
      ? (ref
                .read(trainerClientRecordsProvider)[widget.clientId!]
                ?.programDays
                .toList() ??
            [])
      : [];
  String? _activeDayId;
  bool _renaming = false;
  bool _saving = false;
  bool _confirmClear = false;
  bool _confirmDeleteDay = false;
  String? _confirmDeleteDayId;

  ProgramDay? get _activeDay {
    final id = _activeDayId;
    if (id == null) return null;
    final matches = _days.where((d) => d.id == id);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Mirrors ProgramBuilder.jsx's `saveDays`/`persist` — every edit updates
  /// local state immediately (so it feels instant) and fires the real write
  /// in the background when this is a real client's split; a template
  /// build (no clientId) only lives locally until "Save program".
  void _saveDays(List<ProgramDay> next) {
    setState(() => _days = next);
    final clientId = widget.clientId;
    if (clientId != null) {
      SupabaseService.updateClientProgramDays(
        clientId,
        next,
      ).catchError((Object _) {});
      ref
          .read(trainerClientRecordsProvider.notifier)
          .update(clientId, (r) => r.copyWith(programDays: next));
    }
  }

  void _addDay() {
    final d = ProgramDay(id: _uid(), title: "Day ${_days.length + 1}");
    _saveDays([..._days, d]);
    setState(() => _activeDayId = d.id);
  }

  void _renameDay(String id, String title) => _saveDays(
    _days
        .map(
          (d) => d.id == id
              ? ProgramDay(id: d.id, title: title, exercises: d.exercises)
              : d,
        )
        .toList(),
  );

  void _removeDay(String id) {
    _saveDays(_days.where((d) => d.id != id).toList());
    if (_activeDayId == id) setState(() => _activeDayId = null);
  }

  void _moveDay(String id, int dir) {
    final i = _days.indexWhere((d) => d.id == id);
    final j = i + dir;
    if (j < 0 || j >= _days.length) return;
    final next = [..._days];
    final tmp = next[i];
    next[i] = next[j];
    next[j] = tmp;
    _saveDays(next);
  }

  void _updateExercises(List<ExercisePrescription> exercises) {
    final dayId = _activeDayId;
    if (dayId == null) return;
    _saveDays(
      _days
          .map((d) => d.id == dayId ? d.copyWith(exercises: exercises) : d)
          .toList(),
    );
  }

  Future<void> _addExercise() async {
    final picked = await showExercisePickerSheet(context);
    if (picked == null) return;
    _updateExercises([
      ..._activeDay!.exercises,
      ExercisePrescription(
        id: _uid(),
        exerciseId: picked.id,
        name: picked.name,
        group: picked.primaryMuscle,
      ),
    ]);
  }

  void _updateItem(
    String id,
    ExercisePrescription Function(ExercisePrescription) f,
  ) {
    final day = _activeDay;
    if (day == null) return;
    _updateExercises(day.exercises.map((e) => e.id == id ? f(e) : e).toList());
  }

  void _removeExercise(String id) {
    final day = _activeDay;
    if (day == null) return;
    _updateExercises(day.exercises.where((e) => e.id != id).toList());
  }

  void _resolveFlag(String id) =>
      _updateItem(id, (e) => e.copyWith(clearClientNote: true));

  void _moveExercise(int idx, int dir) {
    final day = _activeDay;
    if (day == null) return;
    final j = idx + dir;
    if (j < 0 || j >= day.exercises.length) return;
    final next = [...day.exercises];
    final tmp = next[idx];
    next[idx] = next[j];
    next[j] = tmp;
    _updateExercises(next);
  }

  void _coupleWithNext(int idx) {
    final day = _activeDay;
    if (day == null) return;
    final groupId = day.exercises[idx].supersetId ?? _uid();
    _updateExercises([
      for (var i = 0; i < day.exercises.length; i++)
        if (i == idx || i == idx + 1)
          day.exercises[i].copyWith(supersetId: groupId)
        else
          day.exercises[i],
    ]);
  }

  void _uncouple(String supersetId) {
    final day = _activeDay;
    if (day == null) return;
    _updateExercises(
      day.exercises
          .map(
            (e) => e.supersetId == supersetId
                ? e.copyWith(clearSupersetId: true)
                : e,
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    final canEdit = isOwner || ref.watch(platformSettingsProvider).coachCanEditClientWorkouts;
    if (!canEdit) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(
          text:
              "Only the owner can build, approve, or assign workout programs.",
        ),
      );
    }
    if (_activeDay == null) {
      return Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel("Workout Split"),
                if (_days.isEmpty)
                  const HintBox(
                    text:
                        "No days yet. Add Day 1 to start building this client's split (e.g. Push / Pull / Legs).",
                  ),
                ..._days.asMap().entries.map((entry) {
                  final i = entry.key;
                  final day = entry.value;
                  return AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _confirmDeleteDayId == day.id
                        ? _InlineDeleteConfirm(
                            label: 'Delete "${day.title}"?',
                            onConfirm: () {
                              _removeDay(day.id);
                              setState(() => _confirmDeleteDayId = null);
                            },
                            onCancel: () =>
                                setState(() => _confirmDeleteDayId = null),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _activeDayId = day.id),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              day.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: AppColors.gold,
                                              ),
                                            ),
                                            Text(
                                              "${day.exercises.length} exercise${day.exercises.length == 1 ? '' : 's'}",
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.mute,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        LucideIcons.chevronRight,
                                        size: 16,
                                        color: AppColors.mute,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ReorderButton(
                                    icon: LucideIcons.chevronUp,
                                    disabled: i == 0,
                                    onTap: () => _moveDay(day.id, -1),
                                  ),
                                  const SizedBox(height: 2),
                                  _ReorderButton(
                                    icon: LucideIcons.chevronDown,
                                    disabled: i == _days.length - 1,
                                    onTap: () => _moveDay(day.id, 1),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => setState(
                                  () => _confirmDeleteDayId = day.id,
                                ),
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: 15,
                                  color: Color(0xFF6B3B3B),
                                ),
                              ),
                            ],
                          ),
                  );
                }),
                BtnGold(
                  full: true,
                  onPressed: _addDay,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 15),
                      SizedBox(width: 6),
                      Text("Add day"),
                    ],
                  ),
                ),
                if (_days.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => setState(() => _saving = true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gold,
                              side: const BorderSide(color: AppColors.goldDim),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.save, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  "Save program",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _confirmClear
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () {
                                          _saveDays([]);
                                          setState(() {
                                            _activeDayId = null;
                                            _confirmClear = false;
                                          });
                                        },
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF6B3B3B,
                                          ),
                                          foregroundColor: const Color(
                                            0xFFF5A0A0,
                                          ),
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        child: const Text(
                                          "Yes",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(
                                          () => _confirmClear = false,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.mute,
                                          side: const BorderSide(
                                            color: AppColors.line,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _confirmClear = true),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.mute,
                                    side: const BorderSide(
                                      color: AppColors.line,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  child: const Text(
                                    "Clear",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_saving)
            _SaveProgramSheet(
              clientId: widget.clientId,
              days: _days,
              onDone: () => setState(() => _saving = false),
              onSaveComplete: () {
                _saveDays([]);
                setState(() {
                  _activeDayId = null;
                  _confirmDeleteDay = false;
                  _saving = false;
                });
              },
            ),
        ],
      );
    }

    final activeDay = _activeDay!;
    void backToAllDays() => setState(() {
      _activeDayId = null;
      _confirmDeleteDay = false;
    });
    return LocalBackScope(
      isOpen: true,
      onBack: backToAllDays,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: backToAllDays,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mute,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(LucideIcons.chevronLeft, size: 15),
              label: const Text("All days", style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 14),
            if (_renaming)
              Row(
                children: [
                  Expanded(
                    child: AppField(
                      controller: TextEditingController(text: activeDay.title),
                      onChanged: (v) => _renameDay(activeDay.id, v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _renaming = false),
                    child: const Text("Done"),
                  ),
                ],
              )
            else if (_confirmDeleteDay)
              _InlineDeleteConfirm(
                label: 'Delete "${activeDay.title}"?',
                onConfirm: () {
                  _removeDay(activeDay.id);
                  setState(() => _confirmDeleteDay = false);
                },
                onCancel: () => setState(() => _confirmDeleteDay = false),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activeDay.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _renaming = true),
                    icon: const Icon(
                      LucideIcons.edit3,
                      size: 15,
                      color: AppColors.mute,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _confirmDeleteDay = true),
                    icon: const Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: Color(0xFF6B3B3B),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            if (activeDay.exercises.isEmpty)
              HintBox(
                text:
                    'No exercises yet for ${activeDay.title}. Tap "Add exercise" to pull from the library.',
              ),
            ...activeDay.exercises.asMap().entries.map((entry) {
              final i = entry.key;
              final ex = entry.value;
              final isSuperset = ex.supersetId != null;
              final groupContinues =
                  isSuperset &&
                  i + 1 < activeDay.exercises.length &&
                  activeDay.exercises[i + 1].supersetId == ex.supersetId;
              final canCouple =
                  i < activeDay.exercises.length - 1 && !isSuperset;
              final flagged = ex.clientNoteText != null;
              return Container(
                margin: EdgeInsets.only(bottom: groupContinues ? 4 : 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(
                    color: flagged
                        ? const Color(0xFFA8632F)
                        : (isSuperset ? AppColors.gold : AppColors.line),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (flagged)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x1AC9784A),
                          border: Border.all(color: const Color(0xFFA8632F)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                LucideIcons.flag,
                                size: 14,
                                color: Color(0xFFD68A4F),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Client flagged this${ex.clientNoteAt != null ? " — ${ex.clientNoteAt}" : ""}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFD68A4F),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    ex.clientNoteText ?? "",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.txt,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _resolveFlag(ex.id),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.mute,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                              ),
                              child: const Text(
                                "Resolve",
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isSuperset)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          "SUPERSET",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _exerciseNumber(i),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ex.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (ex.group != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Tag(text: ex.group!, gold: true),
                                ),
                            ],
                          ),
                        ),
                        _ReorderButton(
                          icon: LucideIcons.chevronUp,
                          disabled: i == 0,
                          onTap: () => _moveExercise(i, -1),
                        ),
                        const SizedBox(width: 4),
                        _ReorderButton(
                          icon: LucideIcons.chevronDown,
                          disabled: i == activeDay.exercises.length - 1,
                          onTap: () => _moveExercise(i, 1),
                        ),
                        IconButton(
                          onPressed: () => _removeExercise(ex.id),
                          icon: const Icon(
                            LucideIcons.trash2,
                            size: 15,
                            color: Color(0xFF6B3B3B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: MiniField(
                            label: "Sets",
                            value: "${ex.sets}",
                            ph: "3",
                            onChange: (v) => _updateItem(
                              ex.id,
                              (e) =>
                                  e.copyWith(sets: int.tryParse(v) ?? e.sets),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: MiniField(
                            label: "Reps",
                            value: "${ex.reps}",
                            ph: "10",
                            onChange: (v) => _updateItem(
                              ex.id,
                              (e) =>
                                  e.copyWith(reps: int.tryParse(v) ?? e.reps),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: MiniField(
                            label: "Weight",
                            value: ex.weight ?? "",
                            ph: "lbs",
                            onChange: (v) => _updateItem(
                              ex.id,
                              (e) => e.copyWith(weight: v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: MiniField(
                            label: "Time",
                            value: ex.time ?? "",
                            ph: "30s or 5m",
                            onChange: (v) =>
                                _updateItem(ex.id, (e) => e.copyWith(time: v)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: MiniField(
                            label: "Distance",
                            value: ex.distance ?? "",
                            ph: "e.g. 1 mi",
                            onChange: (v) => _updateItem(
                              ex.id,
                              (e) => e.copyWith(distance: v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: MiniField(
                            label: "Rest",
                            value: ex.rest ?? "",
                            ph: "60s or 3m",
                            onChange: (v) =>
                                _updateItem(ex.id, (e) => e.copyWith(rest: v)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AppField(
                      controller: TextEditingController(text: ex.notes ?? ""),
                      placeholder: "Exercise notes / form cues (optional)",
                      onChanged: (v) =>
                          _updateItem(ex.id, (e) => e.copyWith(notes: v)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children:
                                [
                                  ("bilateral", "Bilateral"),
                                  ("unilateral", "Unilateral"),
                                ].map((opt) {
                                  final on = (ex.laterality) == opt.$1;
                                  return InkWell(
                                    onTap: () => _updateItem(
                                      ex.id,
                                      (e) => e.copyWith(laterality: opt.$1),
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: on
                                            ? AppColors.gold
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        opt.$2,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: on
                                              ? Colors.white
                                              : AppColors.mute,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                        if (canCouple)
                          _MiniActionButton(
                            label: "Couple with next (superset)",
                            onTap: () => _coupleWithNext(i),
                          ),
                        if (isSuperset)
                          _MiniActionButton(
                            label: "Remove from superset",
                            onTap: () => _uncouple(ex.supersetId!),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            BtnGold(
              full: true,
              onPressed: _addExercise,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.plus, size: 15),
                  SizedBox(width: 6),
                  Text("Add exercise"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderButton extends StatelessWidget {
  const _ReorderButton({
    required this.icon,
    required this.disabled,
    required this.onTap,
  });
  final IconData icon;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 13,
          color: disabled ? AppColors.line : AppColors.mute,
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.mute,
          ),
        ),
      ),
    );
  }
}

class _InlineDeleteConfirm extends StatelessWidget {
  const _InlineDeleteConfirm({
    required this.label,
    required this.onConfirm,
    required this.onCancel,
  });
  final String label;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFFC97F7F)),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onConfirm,
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFF6B3B3B),
            foregroundColor: const Color(0xFFF5A0A0),
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          ),
          child: const Text(
            "Delete",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.mute,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          child: const Text(
            "Cancel",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Mirrors SaveProgramDialog.jsx — snapshots the current day list under a
/// name into client.savedPrograms (+ the shared library), shown as a
/// bottom sheet over the day-list view.
class _SaveProgramSheet extends ConsumerStatefulWidget {
  const _SaveProgramSheet({
    required this.clientId,
    required this.days,
    required this.onDone,
    required this.onSaveComplete,
  });

  final String? clientId;
  final List<ProgramDay> days;
  final VoidCallback onDone;
  final VoidCallback onSaveComplete;

  @override
  ConsumerState<_SaveProgramSheet> createState() => _SaveProgramSheetState();
}

class _SaveProgramSheetState extends ConsumerState<_SaveProgramSheet> {
  final _name = TextEditingController();
  String? _err;
  bool _saved = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _err = "Give the program a name first.");
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final trainerAuth = ref.read(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.read(trainersProvider);
    final me = trainers.where((t) => t.id == trainerAuth);
    final coachName = isOwner
        ? "Owner"
        : (me.isNotEmpty ? me.first.name : "Coach");
    final clientId = widget.clientId;
    final clientName = clientId != null
        ? ref
              .read(trainerRosterProvider)
              .where((c) => c.id == clientId)
              .map((c) => c.name)
              .firstOrElse(null)
        : null;

    final entry = SavedProgram(
      id: _uid(),
      name: name,
      status: "active",
      coachName: coachName,
      createdAt: stamp(),
      modifiedAt: stamp(),
      assignedClientId: clientId,
      assignedClientName: clientName,
      programDays: widget.days,
    );

    try {
      if (clientId != null) {
        final record = ref.read(trainerClientRecordsProvider)[clientId];
        final nextSaved = <SavedProgram>[
          ...(record?.savedPrograms ?? const []),
          entry,
        ];
        await SupabaseService.updateClientSavedPrograms(clientId, nextSaved);
        ref
            .read(trainerClientRecordsProvider.notifier)
            .update(clientId, (r) => r.copyWith(savedPrograms: nextSaved));
      }
      await SupabaseService.upsertProgramLibraryEntry(entry);
      ref.read(programsLibraryProvider.notifier).add(entry);
    } catch (e) {
      if (mounted)
        setState(
          () => _err = "Couldn't save — check your connection and try again.",
        );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) setState(() => _saved = true);
  }

  void _doReset() => widget.onSaveComplete();

  @override
  Widget build(BuildContext context) {
    final clientId = widget.clientId;
    final clientName = clientId != null
        ? ref
              .watch(trainerRosterProvider)
              .where((c) => c.id == clientId)
              .map((c) => c.name)
              .firstOrElse(null)
        : null;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _saved ? null : widget.onDone,
            child: Container(color: Colors.black54),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: SafeArea(
              top: false,
              child: _saved
                  ? _successContent(
                      name: _name.text.trim(),
                      clientName: clientName,
                    )
                  : _formContent(clientName: clientName),
            ),
          ),
        ),
      ],
    );
  }

  Widget _formContent({String? clientName}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Save Workout Program",
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 4),
        if (clientName != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x1433733F),
              border: Border.all(color: AppColors.goldDim),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.user, size: 13, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                      ),
                      children: [
                        const TextSpan(text: "Will be assigned to "),
                        TextSpan(
                          text: clientName,
                          style: const TextStyle(
                            color: AppColors.txt,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(
                          text: " and saved to the Programs Library.",
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              "Saving as a reusable template in the Programs Library — no client assigned yet.",
              style: TextStyle(fontSize: 13, color: AppColors.mute),
            ),
          ),
        AppField(controller: _name, placeholder: "e.g. Push / Pull / Legs"),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _err!,
              style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: BtnGhost(
                onPressed: _busy ? null : widget.onDone,
                child: const Text("Cancel"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: BtnGold(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? "Saving…" : "Save program"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _successContent({required String name, String? clientName}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        const Text("✓", style: TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        Text(
          '"$name" saved!',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.grn,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Saved to ${clientName != null ? "$clientName's profile" : "Programs Library"}. You can keep editing — nothing has been reset.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.mute),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _doReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.mute,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text(
                  "Close",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _saved = false),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0x1F33733F),
                  foregroundColor: AppColors.gold,
                  side: const BorderSide(color: AppColors.goldDim),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text(
                  "Save another version",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

extension _FirstOrElse<T> on Iterable<T> {
  T? firstOrElse(T? fallback) => isNotEmpty ? first : fallback;
}

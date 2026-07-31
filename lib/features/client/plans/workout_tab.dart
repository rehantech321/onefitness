import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/models/program_day.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/models/workout_log.dart";
import "../../../data/providers/client_providers.dart";
import "exercise_set_grid.dart";

/// Mirrors ClientWorkoutWithNotes.jsx: overview day list -> active logging
/// session -> saved confirmation, plus a per-exercise note that can be
/// saved locally or sent straight into the Chat log.
class WorkoutTab extends ConsumerStatefulWidget {
  const WorkoutTab({super.key});

  @override
  ConsumerState<WorkoutTab> createState() => _WorkoutTabState();
}

class _NoteTarget {
  const _NoteTarget({required this.progId, required this.dayId, required this.exId, required this.exName});
  final String progId;
  final String dayId;
  final String exId;
  final String exName;
}

class _WorkoutTabState extends ConsumerState<WorkoutTab> {
  String? _selectedProgId;
  String? _dayId;
  bool _sessionStarted = false;
  final Map<String, SetDraft> _sessionData = {};
  bool _saved = false;

  void _startDay(String dayId) => setState(() {
        _dayId = dayId;
        _sessionStarted = true;
        _sessionData.clear();
      });

  void _onSetChange(String exerciseName, int setNum, String field, Object? value) {
    final key = "${exerciseName}__$setNum";
    final draft = _sessionData.putIfAbsent(key, () => SetDraft());
    if (field == "reps") draft.reps = value as int?;
    if (field == "weight") draft.weight = value as double?;
  }

  void _saveSession(SavedProgram prog, ProgramDay day) {
    final exercises = day.exercises.map((ex) {
      final sets = List.generate(ex.sets > 0 ? ex.sets : 3, (i) {
        final setNum = i + 1;
        final d = _sessionData["${ex.name}__$setNum"];
        return LoggedSet(
          setNum: setNum,
          targetReps: ex.reps,
          completedReps: d?.reps,
          completedWeight: d?.weight,
          completed: d?.reps != null || d?.weight != null,
        );
      });
      return LoggedExercise(name: ex.name, sets: sets);
    }).toList();

    final entry = WorkoutLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: isoToday(),
      programId: prog.id,
      programName: prog.name,
      dayId: day.id,
      dayTitle: day.title,
      loggedAt: DateTime.now().toIso8601String(),
      exercises: exercises,
    );

    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(
          workoutLogs: [...r.workoutLogs, entry],
          loggedDates: r.loggedDates.contains(isoToday()) ? r.loggedDates : [...r.loggedDates, isoToday()],
        ));

    setState(() {
      _sessionData.clear();
      _saved = true;
      _sessionStarted = false;
    });
  }

  void _openNoteSheet(_NoteTarget target, String? existingNote) {
    final controller = TextEditingController(text: "");
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasText = controller.text.trim().isNotEmpty;
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Note on ${target.exName}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text("Your coach will be notified.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.txt, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "e.g. Left shoulder feels tight on this one",
                      hintStyle: const TextStyle(color: AppColors.mute),
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: !hasText
                              ? null
                              : () {
                                  _saveNote(target, controller.text.trim(), sendToCoach: false);
                                  Navigator.of(sheetContext).pop();
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.gold,
                            side: const BorderSide(color: AppColors.goldDim),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text("Save Note", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BtnGold(
                          onPressed: !hasText
                              ? null
                              : () {
                                  _saveNote(target, controller.text.trim(), sendToCoach: true);
                                  Navigator.of(sheetContext).pop();
                                },
                          child: const Text("Send to Coach", style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text("Cancel", style: TextStyle(color: AppColors.mute, fontSize: 12)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _saveNote(_NoteTarget target, String text, {required bool sendToCoach}) {
    ref.read(clientRecordProvider.notifier).update((r) {
      final updatedPrograms = r.savedPrograms.map((prog) {
        if (prog.id != target.progId) return prog;
        return prog.copyWith(
          programDays: prog.programDays.map((day) {
            if (day.id != target.dayId) return day;
            return day.copyWith(
              exercises: day.exercises
                  .map((ex) => ex.id == target.exId
                      ? ex.copyWith(clientNoteText: text, clientNoteAt: stamp())
                      : ex)
                  .toList(),
            );
          }).toList(),
        );
      }).toList();

      var comms = r.comms;
      if (sendToCoach) {
        final entry = CommMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          who: "client",
          text: "\u{1F4DD} Workout note on ${target.exName}: $text",
          at: stamp(),
          trainerId: null,
        );
        comms = [entry, ...comms];
      }
      return r.copyWith(savedPrograms: updatedPrograms, comms: comms);
    });

    if (sendToCoach && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✓ Note sent to your coach.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final programs = client.savedPrograms.where((p) => p.status == "active").toList();

    if (programs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(text: "No active workout program yet. Your coach will assign one to your profile."),
      );
    }

    final prog = programs.firstWhere((p) => p.id == _selectedProgId, orElse: () => programs.first);
    final days = prog.programDays;
    final activeDay = days.firstWhere((d) => d.id == _dayId, orElse: () => days.isNotEmpty ? days.first : const ProgramDay(id: "", title: ""));

    if (_saved) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text("\u{1F4AA}", style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            const Text("Session logged!", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            BtnGold(
              onPressed: () => setState(() => _saved = false),
              full: true,
              child: const Text("Back to Days"),
            ),
          ],
        ),
      );
    }

    final allNotes = getClientProgramNotes(client);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allNotes.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.07),
                border: Border.all(color: const Color(0xFF6B3B3B)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "\u{1F4DD} Your program notes (${allNotes.length})",
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger),
                  ),
                  const SizedBox(height: 6),
                  ...allNotes.map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                            children: [
                              TextSpan(text: "${n.label}: ", style: const TextStyle(color: AppColors.txt)),
                              TextSpan(text: n.text),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),

          if (programs.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: programs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final p = programs[i];
                    final on = p.id == prog.id;
                    return _Chip(
                      label: p.name,
                      selected: on,
                      onTap: () => setState(() {
                        _selectedProgId = p.id;
                        _dayId = null;
                        _sessionStarted = false;
                        _sessionData.clear();
                      }),
                    );
                  },
                ),
              ),
            ),

          if (!_sessionStarted) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Builder(builder: (context) {
                final cycleCompleted = getCurrentCycleCompletedDays(client, days);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(prog.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    if (days.isEmpty) const HintBox(text: "No days in this program yet."),
                    ...days.map((d) {
                      final completed = cycleCompleted.contains(d.id);
                      final exCount = d.exercises.length;
                      return AppCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      if (completed) ...[
                                        const SizedBox(width: 6),
                                        const Icon(LucideIcons.check, size: 14, color: AppColors.grn),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text("$exCount exercise${exCount != 1 ? 's' : ''}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => _startDay(d.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Start Session", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _sessionStarted = false),
                        style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero),
                        icon: const Icon(LucideIcons.chevronLeft, size: 15),
                        label: const Text("Days", style: TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        child: Text(
                          activeDay.title,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  if (days.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 14),
                      child: Builder(builder: (context) {
                        final cycleCompleted = getCurrentCycleCompletedDays(client, days);
                        return SizedBox(
                          height: 34,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: days.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (context, i) {
                              final d = days[i];
                              return _Chip(
                                label: d.title,
                                selected: activeDay.id == d.id,
                                trailingCheck: cycleCompleted.contains(d.id),
                                onTap: () => setState(() {
                                  _dayId = d.id;
                                  _sessionData.clear();
                                }),
                              );
                            },
                          ),
                        );
                      }),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: const [
                      _LegendDot(color: AppColors.grn, label: "Hit target reps"),
                      _LegendDot(color: Color(0xFF00E676), label: "Weight PR"),
                      _LegendDot(color: AppColors.gold, label: "Same weight"),
                      _LegendDot(color: AppColors.danger, label: "Weight dropped"),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...activeDay.exercises.map((ex) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExerciseSetGrid(
                              key: ValueKey(ex.id),
                              exercise: ex,
                              client: client,
                              sessionData: _sessionData,
                              onSetChange: _onSetChange,
                              dayId: activeDay.id,
                            ),
                            if (ex.clientNoteText != null && ex.clientNoteText!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: 0.06),
                                  border: Border.all(color: const Color(0xFF6B3B3B)),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  "\u{1F4DD} ${ex.clientNoteText}",
                                  style: const TextStyle(fontSize: 12, color: AppColors.mute),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: OutlinedButton(
                                  onPressed: () => _openNoteSheet(
                                    _NoteTarget(progId: prog.id, dayId: activeDay.id, exId: ex.id, exName: ex.name),
                                    ex.clientNoteText,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.mute,
                                    side: const BorderSide(color: AppColors.line),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    ex.clientNoteText != null && ex.clientNoteText!.isNotEmpty ? "\u{1F4DD} Edit Note" : "+ Note",
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (_sessionData.isNotEmpty)
                    BtnGold(onPressed: () => _saveSession(prog, activeDay), full: true, child: const Text("Save session log")),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.trailingCheck = false});
  final String label;
  final bool selected;
  final bool trailingCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.gold : AppColors.mute)),
            if (trailingCheck) ...[
              const SizedBox(width: 5),
              const Icon(LucideIcons.check, size: 13, color: AppColors.grn),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
      ],
    );
  }
}

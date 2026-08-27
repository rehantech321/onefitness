import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../core/theme/app_colors.dart";
import "../../core/utils/date_utils.dart";
import "../../core/utils/program_utils.dart";
import "../../core/widgets/widgets.dart";
import "../../data/models/client_record.dart";
import "../../data/models/exercise_prescription.dart";
import "../../data/models/program_day.dart";
import "../../data/models/saved_program.dart";
import "../../data/models/workout_log.dart";
import "../client/plans/exercise_set_grid.dart";

/// The session-logging state machine — active-programs list -> day list
/// with "Start Session" -> active-day ExerciseSetGrids -> Save -> "Session
/// logged!" confirmation. Extracted out of what used to be
/// `WorkoutTab`'s private state so a coach logging a session *for* a
/// client (trainer_home_screen.dart's Start Session) runs through the
/// exact same logic a client logging their own session does
/// (workout_tab.dart) — not a parallel reimplementation that could drift.
///
/// Deliberately takes [client] as a plain snapshot rather than reading a
/// provider itself: the two callers watch different providers
/// (`clientRecordProvider` for a client logging themselves,
/// `trainerClientRecordsProvider` for a coach logging on a client's
/// behalf) and persist to different local state — that's entirely the
/// caller's job via [onSave]. [loggedBy] and [onSave] together let each
/// caller decide who's logging and how the result gets saved (both real
/// backend + local state), rather than baking that into this widget.
class SessionLoggerView extends StatefulWidget {
  const SessionLoggerView({
    super.key,
    required this.client,
    required this.onSave,
    this.loggedBy = "client",
    this.emptyProgramText =
        "No active workout program yet. Your coach will assign one to your profile.",
    this.exerciseFooterBuilder,
  });

  final ClientRecord client;

  /// "client" (self-logged) | "coach" (logged on the client's behalf).
  final String loggedBy;

  /// Persists the newly-completed entry (real backend write + the
  /// caller's own local provider update) — throw to signal failure, which
  /// this widget surfaces as a SnackBar without losing the in-progress
  /// session.
  final Future<void> Function(WorkoutLogEntry entry) onSave;

  final String emptyProgramText;

  /// Optional extra content rendered under each exercise's set grid — used
  /// by the client's own view to show/edit a per-exercise note to their
  /// coach (not offered when a coach is logging on a client's behalf,
  /// since there's no one to notify).
  final Widget Function(
    SavedProgram prog,
    ProgramDay day,
    ExercisePrescription ex,
  )?
  exerciseFooterBuilder;

  @override
  State<SessionLoggerView> createState() => _SessionLoggerViewState();
}

class _SessionLoggerViewState extends State<SessionLoggerView> {
  String? _selectedProgId;
  String? _dayId;
  bool _sessionStarted = false;
  final Map<String, SetDraft> _sessionData = {};
  bool _saved = false;
  bool _saving = false;

  void _startDay(String dayId) => setState(() {
    _dayId = dayId;
    _sessionStarted = true;
    _sessionData.clear();
  });

  // Mutating _sessionData alone doesn't tell this State to rebuild — the
  // Save button's `if (_sessionData.isNotEmpty)` check below only
  // re-evaluates on a real setState. ExerciseSetGrid already calls its
  // own local setState per keystroke (to redraw its own hit/PR
  // highlighting), but that only rebuilds itself, not this parent.
  void _onSetChange(
    String exerciseName,
    int setNum,
    String field,
    Object? value,
  ) {
    setState(() {
      final key = "${exerciseName}__$setNum";
      final draft = _sessionData.putIfAbsent(key, () => SetDraft());
      if (field == "reps") draft.reps = value as int?;
      if (field == "weight") draft.weight = value as double?;
    });
  }

  Future<void> _saveSession(SavedProgram prog, ProgramDay day) async {
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
      loggedBy: widget.loggedBy,
    );

    setState(() => _saving = true);
    try {
      await widget.onSave(entry);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
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
    if (!mounted) return;
    setState(() {
      _saving = false;
      _sessionData.clear();
      _saved = true;
      _sessionStarted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final programs = client.savedPrograms
        .where((p) => p.status == "active")
        .toList();

    if (programs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: HintBox(text: widget.emptyProgramText),
      );
    }

    final prog = programs.firstWhere(
      (p) => p.id == _selectedProgId,
      orElse: () => programs.first,
    );
    final days = prog.programDays;
    final activeDay = days.firstWhere(
      (d) => d.id == _dayId,
      orElse: () =>
          days.isNotEmpty ? days.first : const ProgramDay(id: "", title: ""),
    );

    if (_saved) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text("\u{1F4AA}", style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            const Text(
              "Session logged!",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              child: Builder(
                builder: (context) {
                  final cycleCompleted = getCurrentCycleCompletedDays(
                    client,
                    days,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          prog.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (days.isEmpty)
                        const HintBox(text: "No days in this program yet."),
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
                                        Expanded(
                                          child: Text(
                                            d.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (completed) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            LucideIcons.check,
                                            size: 14,
                                            color: AppColors.grn,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "$exCount exercise${exCount != 1 ? 's' : ''}",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.mute,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => _startDay(d.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  "Start Session",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
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
                        onPressed: () =>
                            setState(() => _sessionStarted = false),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.mute,
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(LucideIcons.chevronLeft, size: 15),
                        label: const Text(
                          "Days",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          activeDay.title,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (days.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 14),
                      child: Builder(
                        builder: (context) {
                          final cycleCompleted = getCurrentCycleCompletedDays(
                            client,
                            days,
                          );
                          return SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: days.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 6),
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
                        },
                      ),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: const [
                      _LegendDot(
                        color: AppColors.grn,
                        label: "Hit target reps",
                      ),
                      _LegendDot(color: Color(0xFF00E676), label: "Weight PR"),
                      _LegendDot(color: AppColors.gold, label: "Same weight"),
                      _LegendDot(
                        color: AppColors.danger,
                        label: "Weight dropped",
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...activeDay.exercises.map(
                    (ex) => Padding(
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
                          if (widget.exerciseFooterBuilder != null)
                            widget.exerciseFooterBuilder!(prog, activeDay, ex),
                        ],
                      ),
                    ),
                  ),
                  if (_sessionData.isNotEmpty)
                    BtnGold(
                      onPressed: _saving
                          ? null
                          : () => _saveSession(prog, activeDay),
                      full: true,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text("Save session log"),
                    ),
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
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingCheck = false,
  });
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
          color: selected
              ? AppColors.gold.withValues(alpha: 0.12)
              : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.gold : AppColors.mute,
              ),
            ),
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
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.mute),
        ),
      ],
    );
  }
}

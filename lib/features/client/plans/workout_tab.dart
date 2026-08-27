import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/models/exercise_prescription.dart";
import "../../../data/models/program_day.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/models/workout_log.dart";
import "../../../data/providers/client_providers.dart";
import "../../shared/session_logger_view.dart";

/// Mirrors ClientWorkoutWithNotes.jsx: overview day list -> active logging
/// session -> saved confirmation (SessionLoggerView, shared with the
/// coach's own Start Session flow — see trainer_home_screen.dart), plus a
/// per-exercise note that can be saved locally or sent straight into the
/// Chat log — a client-only concern, so it wraps the shared logger rather
/// than living inside it.
class WorkoutTab extends ConsumerStatefulWidget {
  const WorkoutTab({super.key});

  @override
  ConsumerState<WorkoutTab> createState() => _WorkoutTabState();
}

class _NoteTarget {
  const _NoteTarget({
    required this.progId,
    required this.dayId,
    required this.exId,
    required this.exName,
  });
  final String progId;
  final String dayId;
  final String exId;
  final String exName;
}

class _WorkoutTabState extends ConsumerState<WorkoutTab> {
  Future<void> _saveSession(WorkoutLogEntry entry) async {
    final client = ref.read(clientRecordProvider);
    final updatedLogs = [...client.workoutLogs, entry];
    await SupabaseService.updateClientWorkoutLogs(client.id, updatedLogs);
    ref
        .read(clientRecordProvider.notifier)
        .update(
          (r) => r.copyWith(
            workoutLogs: updatedLogs,
            loggedDates: r.loggedDates.contains(isoToday())
                ? r.loggedDates
                : [...r.loggedDates, isoToday()],
          ),
        );
  }

  void _openNoteSheet(_NoteTarget target, String? existingNote) {
    final controller = TextEditingController(text: "");
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
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
                  Text(
                    "Note on ${target.exName}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Your coach will be notified.",
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.line),
                      ),
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
                                  _saveNote(
                                    target,
                                    controller.text.trim(),
                                    sendToCoach: false,
                                  );
                                  Navigator.of(sheetContext).pop();
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.gold,
                            side: const BorderSide(color: AppColors.goldDim),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text(
                            "Save Note",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BtnGold(
                          onPressed: !hasText
                              ? null
                              : () {
                                  _saveNote(
                                    target,
                                    controller.text.trim(),
                                    sendToCoach: true,
                                  );
                                  Navigator.of(sheetContext).pop();
                                },
                          child: const Text(
                            "Send to Coach",
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: AppColors.mute, fontSize: 12),
                    ),
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
                  .map(
                    (ex) => ex.id == target.exId
                        ? ex.copyWith(
                            clientNoteText: text,
                            clientNoteAt: stamp(),
                          )
                        : ex,
                  )
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

  Widget _exerciseFooter(
    SavedProgram prog,
    ProgramDay day,
    ExercisePrescription ex,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                _NoteTarget(
                  progId: prog.id,
                  dayId: day.id,
                  exId: ex.id,
                  exName: ex.name,
                ),
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
                ex.clientNoteText != null && ex.clientNoteText!.isNotEmpty
                    ? "\u{1F4DD} Edit Note"
                    : "+ Note",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final allNotes = getClientProgramNotes(client);

    return Column(
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
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 6),
                ...allNotes.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mute,
                        ),
                        children: [
                          TextSpan(
                            text: "${n.label}: ",
                            style: const TextStyle(color: AppColors.txt),
                          ),
                          TextSpan(text: n.text),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: SessionLoggerView(
            client: client,
            onSave: _saveSession,
            exerciseFooterBuilder: _exerciseFooter,
          ),
        ),
      ],
    );
  }
}

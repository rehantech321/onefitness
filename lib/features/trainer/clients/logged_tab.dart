import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

const _dirMeta = {
  "up": (arrow: "↑", color: Color(0xFF00E676), label: "Increased"),
  "down": (arrow: "↓", color: AppColors.danger, label: "Decreased"),
  "same": (arrow: "=", color: AppColors.gold, label: "Maintained"),
  "new": (arrow: "•", color: AppColors.mute, label: "First logged"),
};

/// Mirrors TrainerView.jsx's "logs" tab (`<LoggedSessions client readOnly />`)
/// — the same read-only progression history the client sees of their own
/// sessions, from the coach's side, plus a per-session comment box
/// (Notifications spec — "Coach comments on a workout"). Session Feedback
/// isn't modeled yet.
class LoggedTab extends ConsumerStatefulWidget {
  const LoggedTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<LoggedTab> createState() => _LoggedTabState();
}

class _LoggedTabState extends ConsumerState<LoggedTab> {
  final Map<String, TextEditingController> _controllers = {};
  String? _savingId;

  TextEditingController _controllerFor(String logId, String? current) =>
      _controllers.putIfAbsent(logId, () => TextEditingController(text: current ?? ""));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveComment(String logId) async {
    final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
    if (record == null) return;
    final text = _controllers[logId]?.text.trim() ?? "";
    setState(() => _savingId = logId);
    try {
      final next = record.workoutLogs
          .map((l) => l.id == logId ? l.copyWith(coachComment: text, coachCommentAt: stamp()) : l)
          .toList();
      await SupabaseService.updateClientWorkoutLogs(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(workoutLogs: next));
      if (text.isNotEmpty) {
        final info = ref.read(trainerRosterProvider).where((c) => c.id == widget.clientId);
        if (info.isNotEmpty) {
          notifyCoachComment(toEmail: info.first.email ?? "", toName: info.first.name, kind: "workout session");
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Comment saved.")));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    final days = record != null
        ? getDayProgressionSummary(record)
        : const <DayProgression>[];

    if (days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(text: "Nothing logged yet for this client."),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Logged Sessions"),
          ...days.map((day) {
            final logMatches = record!.workoutLogs.where((l) => l.id == day.sourceId);
            final log = logMatches.isEmpty ? null : logMatches.first;
            return CollapsibleSection(
              title: day.dayTitle,
              meta: Text(
                "${_niceDate(day.date)} · ${day.loggedBy == "coach" ? "Logged by coach" : "Self-logged"}",
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
              children: [
                ...day.exercises.map(
                  (ex) => CollapsibleSection(
                    title: ex.name,
                    meta: Text(
                      "${_dirMeta[ex.direction]!.label} ${_dirMeta[ex.direction]!.arrow}",
                      style: TextStyle(
                        color: _dirMeta[ex.direction]!.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    children: ex.sets
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppColors.line),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Set ${s.setNum}",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.mute,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      s.prevWeight != null
                                          ? "${_fmtNum(s.prevWeight!)} lbs → ${_fmtNum(s.weight)} lbs"
                                          : "${_fmtNum(s.weight)} lbs",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.txt,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _dirMeta[s.direction ?? "new"]!.arrow,
                                      style: TextStyle(
                                        color: _dirMeta[s.direction ?? "new"]!
                                            .color,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (log != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("COACH COMMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mute, letterSpacing: 0.5)),
                        const SizedBox(height: 6),
                        AppField(
                          controller: _controllerFor(log.id, log.coachComment),
                          placeholder: "Leave a note on this session…",
                          maxLines: 2,
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: BtnGhost(
                            onPressed: _savingId == log.id ? null : () => _saveComment(log.id),
                            child: Text(_savingId == log.id ? "Saving…" : "Save comment"),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

String _fmtNum(double n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

String _niceDate(String iso) {
  final d = DateTime.parse(iso);
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return "${weekdays[d.weekday % 7]}, ${months[d.month - 1]} ${d.day}";
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
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
/// sessions, from the coach's side. Session Feedback isn't modeled yet.
class LoggedTab extends ConsumerWidget {
  const LoggedTab({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[clientId];
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
          ...days.map(
            (day) => CollapsibleSection(
              title: day.dayTitle,
              meta: Text(
                "${_niceDate(day.date)} · ${day.loggedBy == "coach" ? "Logged by coach" : "Self-logged"}",
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
              children: day.exercises
                  .map(
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
                  )
                  .toList(),
            ),
          ),
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

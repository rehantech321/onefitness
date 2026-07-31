import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

class _DirMeta {
  const _DirMeta({required this.arrow, required this.color, required this.label});
  final String arrow;
  final Color color;
  final String label;
}

const _dirMeta = {
  "up": _DirMeta(arrow: "↑", color: Color(0xFF00E676), label: "Increased"),
  "down": _DirMeta(arrow: "↓", color: AppColors.danger, label: "Decreased"),
  "same": _DirMeta(arrow: "=", color: AppColors.gold, label: "Maintained"),
  "new": _DirMeta(arrow: "•", color: AppColors.mute, label: "First logged"),
};

/// Mirrors LoggedSessions.jsx (client, read/write) — nested collapsible
/// history of every logged workout day, each exercise showing whether it
/// trended up/down/held vs. the session before it.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientRecordProvider);
    final days = getDayProgressionSummary(client);

    if (days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(text: "Nothing logged yet. Log a session from your Dashboard."),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Your history"),
          ...days.map((day) => CollapsibleSection(
                title: day.dayTitle,
                meta: Text(_niceDate(day.date), style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                children: day.exercises
                    .map((ex) => CollapsibleSection(
                          title: ex.name,
                          meta: Text(
                            "${_dirMeta[ex.direction]!.label} ${_dirMeta[ex.direction]!.arrow}",
                            style: TextStyle(color: _dirMeta[ex.direction]!.color, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          children: ex.sets
                              .map((s) => Container(
                                    padding: const EdgeInsets.symmetric(vertical: 7),
                                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("Set ${s.setNum}", style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                                        Row(
                                          children: [
                                            Text(
                                              s.prevWeight != null
                                                  ? "${_fmtNum(s.prevWeight!)} lbs → ${_fmtNum(s.weight)} lbs"
                                                  : "${_fmtNum(s.weight)} lbs",
                                              style: const TextStyle(fontSize: 13, color: AppColors.txt),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _dirMeta[s.direction ?? "new"]!.arrow,
                                              style: TextStyle(color: _dirMeta[s.direction ?? "new"]!.color, fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ))
                    .toList(),
              )),
        ],
      ),
    );
  }
}

String _fmtNum(double n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

String _niceDate(String iso) {
  final d = DateTime.parse(iso);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return "${weekdays[d.weekday % 7]}, ${months[d.month - 1]} ${d.day}";
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/squad_chat_message.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "line_chart_painter.dart";

const _chartColors = [Color(0xFF00E676), AppColors.gold, Color(0xFF64B5F6), Color(0xFFFF7043), Color(0xFFCE93D8), Color(0xFF80DEEA)];

/// Mirrors LogProgressPage.jsx's "Lifts" tab — pick up to 6 exercises from
/// workout history, chart their heaviest completed set over time.
class ExerciseLiftsTab extends ConsumerStatefulWidget {
  const ExerciseLiftsTab({super.key});

  @override
  ConsumerState<ExerciseLiftsTab> createState() => _ExerciseLiftsTabState();
}

class _ExerciseLiftsTabState extends ConsumerState<ExerciseLiftsTab> {
  final List<String> _selected = [];
  bool _sharing = false;

  Future<void> _shareWithSquad(Map<String, List<double?>> seriesByName) async {
    if (_sharing) return;
    final info = ref.read(clientInfoProvider);
    final squad = ref.read(squadsProvider.notifier).squadFor(info.id);
    if (squad == null) return;
    final entry = SquadChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      from: info.id,
      at: stamp(),
      type: "shared_progress",
      shareKind: "exercises",
      payload: {
        "exercises": _selected,
        "series": seriesByName.map((k, v) => MapEntry(k, v.whereType<double>().toList())),
      },
    );
    setState(() => _sharing = true);
    final ok = await mutateSquad(ref, squad, (s) => s.copyWith(chat: [entry, ...s.chat]));
    if (!mounted) return;
    setState(() => _sharing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Shared to Squad chat" : "Couldn't share — check your connection and try again.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final info = ref.watch(clientInfoProvider);
    final squad = ref.watch(squadsProvider.notifier).squadFor(info.id);

    // name -> [(date, weight)], mirrors LogProgressPage.jsx's exerciseHistory build-up.
    final history = <String, List<(String, double)>>{};
    for (final log in client.workoutLogs) {
      for (final ex in log.exercises) {
        final doneWeights = ex.sets.where((s) => s.completed && (s.completedWeight ?? 0) > 0).map((s) => s.completedWeight!);
        if (doneWeights.isEmpty) continue;
        final maxW = doneWeights.reduce((a, b) => a > b ? a : b);
        history.putIfAbsent(ex.name, () => []).add((log.date, maxW));
      }
    }
    final names = history.keys.toList()..sort();

    final allDates = {for (final n in _selected) ...history[n]!.map((e) => e.$1)}.toList()..sort();
    final canChart = _selected.isNotEmpty && allDates.length >= 2;

    List<double?>? seriesFor(String name) {
      final byDate = {for (final e in history[name] ?? const <(String, double)>[]) e.$1: e.$2};
      return allDates.map((d) => byDate[d]).toList();
    }

    final allWeights = _selected.expand((n) => history[n]?.map((e) => e.$2) ?? const <double>[]).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Choose exercises to chart (max 6)"),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: names.map((name) {
              final sel = _selected.contains(name);
              final colorIdx = _selected.indexOf(name);
              final color = sel ? _chartColors[colorIdx % _chartColors.length] : AppColors.mute;
              return InkWell(
                onTap: () => setState(() {
                  if (sel) {
                    _selected.remove(name);
                  } else if (_selected.length < 6) {
                    _selected.add(name);
                  }
                }),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? color.withValues(alpha: 0.13) : Colors.transparent,
                    border: Border.all(color: sel ? color : AppColors.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (names.isEmpty)
            const HintBox(text: "Log some workouts first — exercise charts will appear here automatically.")
          else if (_selected.isNotEmpty && !canChart)
            const HintBox(text: "Need more workout history to chart.")
          else if (canChart)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: LineChartPainter(
                        series: [
                          for (var i = 0; i < _selected.length; i++)
                            ChartSeries(values: seriesFor(_selected[i])!, color: _chartColors[i % _chartColors.length]),
                        ],
                        minY: allWeights.reduce((a, b) => a < b ? a : b),
                        maxY: allWeights.reduce((a, b) => a > b ? a : b),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _selected.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 12, height: 3, color: _chartColors[i % _chartColors.length]),
                            const SizedBox(width: 5),
                            Text(_selected[i], style: TextStyle(fontSize: 11, color: _chartColors[i % _chartColors.length])),
                          ],
                        ),
                    ],
                  ),
                  if (squad != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _sharing ? null : () => _shareWithSquad({for (final n in _selected) n: seriesFor(n)!}),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.goldDim),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                        icon: _sharing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
                            : const Icon(LucideIcons.users2, size: 14),
                        label: Text(_sharing ? "Sharing…" : "Share with Squad", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

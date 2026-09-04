import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/measurement.dart";
import "../../../data/models/squad_chat_message.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "line_chart_painter.dart";

const _measureFieldKeys = ["weight", "bodyfat", "chest", "waist", "hips", "arms", "thighs"];
const _measureFieldLabels = ["Weight", "Body Fat %", "Chest", "Waist", "Hips", "Arms", "Thighs"];

/// Mirrors LogProgressPage.jsx's "Body" tab + Measurements.jsx: a bodyweight
/// sparkline, then the add/list/delete measurement log.
class MeasurementsTab extends ConsumerStatefulWidget {
  const MeasurementsTab({super.key, required this.rangeDays});
  final int rangeDays; // 0 = all time

  @override
  ConsumerState<MeasurementsTab> createState() => _MeasurementsTabState();
}

class _MeasurementsTabState extends ConsumerState<MeasurementsTab> {
  bool _adding = false;
  bool _saving = false;
  bool _sharing = false;
  String? _removingId;
  String? _error;
  final _dateController = TextEditingController(text: isoToday());
  final Map<String, TextEditingController> _fieldControllers = {
    for (final k in _measureFieldKeys) k: TextEditingController(),
  };

  @override
  void dispose() {
    _dateController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final values = {for (final k in _measureFieldKeys) k: _fieldControllers[k]!.text.trim()};
    final entry = Measurement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: _dateController.text.trim().isEmpty ? isoToday() : _dateController.text.trim(),
      weight: values["weight"]!.isEmpty ? null : values["weight"],
      bodyfat: values["bodyfat"]!.isEmpty ? null : values["bodyfat"],
      chest: values["chest"]!.isEmpty ? null : values["chest"],
      waist: values["waist"]!.isEmpty ? null : values["waist"],
      hips: values["hips"]!.isEmpty ? null : values["hips"],
      arms: values["arms"]!.isEmpty ? null : values["arms"],
      thighs: values["thighs"]!.isEmpty ? null : values["thighs"],
    );
    final client = ref.read(clientRecordProvider);
    final next = [entry, ...client.measurements]..sort((a, b) => b.date.compareTo(a.date));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.updateClientMeasurements(client.id, next);
      ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(measurements: next));
      final info = ref.read(clientInfoProvider);
      final goalWeight = parseLeadingNum(
        (client.intake["nutritional"]?.answers["goalWeight"] ?? client.intake["personalTraining"]?.answers["goalWeight"])?.toString(),
      );
      notifyGoalReachedIfCrossed(
        toEmail: info.email ?? "",
        toName: info.name,
        priorMeasurements: client.measurements,
        latest: entry,
        goalWeight: goalWeight,
      );
      for (final c in _fieldControllers.values) {
        c.clear();
      }
      _dateController.text = isoToday();
      if (mounted) setState(() { _adding = false; _saving = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save — check your connection and try again.";
        });
      }
    }
  }

  Future<void> _shareWithSquad(List<double> weights) async {
    if (_sharing) return;
    final info = ref.read(clientInfoProvider);
    final squad = ref.read(squadsProvider.notifier).squadFor(info.id);
    if (squad == null) return;
    final trend = weights.length >= 2
        ? (weights.last > weights.first ? "up" : (weights.last < weights.first ? "down" : "flat"))
        : "flat";
    final entry = SquadChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      from: info.id,
      at: stamp(),
      type: "shared_progress",
      shareKind: "measurements",
      payload: {
        "metric": "weight",
        "rangeDays": widget.rangeDays,
        "values": weights,
        "latestValue": weights.isNotEmpty ? weights.last : null,
        "trend": trend,
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

  Future<void> _remove(String id) async {
    if (_removingId != null) return;
    final client = ref.read(clientRecordProvider);
    final next = client.measurements.where((m) => m.id != id).toList();
    setState(() {
      _removingId = id;
      _error = null;
    });
    try {
      await SupabaseService.updateClientMeasurements(client.id, next);
      ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(measurements: next));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't delete — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final info = ref.watch(clientInfoProvider);
    final squad = ref.watch(squadsProvider.notifier).squadFor(info.id);
    final cutoff = widget.rangeDays == 0 ? null : isoDate(DateTime.parse(isoToday()).subtract(Duration(days: widget.rangeDays)));
    final entries = client.measurements.where((m) => cutoff == null || m.date.compareTo(cutoff) >= 0).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final weights = entries.where((m) => m.weight != null).map((m) => double.tryParse(m.weight!)).whereType<double>().toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (weights.length >= 2)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Bodyweight Over Time", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: LineChartPainter(
                        series: [ChartSeries(values: weights, color: AppColors.grn)],
                        minY: weights.reduce((a, b) => a < b ? a : b),
                        maxY: weights.reduce((a, b) => a > b ? a : b),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const HintBox(text: "Log at least 2 measurements to see charts."),
          if (squad != null && entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sharing ? null : () => _shareWithSquad(weights),
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
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Measurements"),
              if (!_adding)
                TextButton.icon(
                  onPressed: () => setState(() => _adding = true),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: const Text("Log", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (_adding)
            LocalBackScope(
              isOpen: true,
              onBack: () => setState(() => _adding = false),
              child: AppCard(
              borderColor: AppColors.goldDim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldLabeled(label: "Date", child: AppField(controller: _dateController)),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.6,
                    children: List.generate(
                      _measureFieldKeys.length,
                      (i) => MiniField(label: _measureFieldLabels[i], value: _fieldControllers[_measureFieldKeys[i]]!.text, onChange: (v) => _fieldControllers[_measureFieldKeys[i]]!.text = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: BtnGold(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [Icon(LucideIcons.check, size: 15, color: Colors.white), SizedBox(width: 6), Text("Save")],
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BtnGhost(onPressed: _saving ? null : () => setState(() => _adding = false), child: const Text("Cancel")),
                    ],
                  ),
                ],
              ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
            ),
          if (entries.isEmpty && !_adding)
            const HintBox(text: "No measurements logged yet. Track weight and body measurements over time.")
          else
            ...entries.reversed.map((m) => AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dayLabel(m.date), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold, fontSize: 13)),
                          _removingId == m.id
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6B3B3B)),
                                )
                              : IconButton(
                                  onPressed: _removingId == null ? () => _remove(m.id) : null,
                                  icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: m.fields.where((f) => f.$3 != null).map((f) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.$2.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5)),
                              Text(f.$3!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ],
                          );
                        }).toList(),
                      ),
                      if (m.coachComment != null && m.coachComment!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.goldDim),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("COACH'S NOTE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gold, letterSpacing: 0.5)),
                                const SizedBox(height: 4),
                                Text(m.coachComment!, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

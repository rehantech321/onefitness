import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/measurement.dart";
import "../../../data/providers/client_providers.dart";
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

  void _save() {
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
    ref.read(clientRecordProvider.notifier).update((r) {
      final next = [entry, ...r.measurements]..sort((a, b) => b.date.compareTo(a.date));
      return r.copyWith(measurements: next);
    });
    for (final c in _fieldControllers.values) {
      c.clear();
    }
    _dateController.text = isoToday();
    setState(() => _adding = false);
  }

  void _remove(String id) {
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(measurements: r.measurements.where((m) => m.id != id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
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
            AppCard(
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
                          onPressed: _save,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(LucideIcons.check, size: 15, color: Colors.white), SizedBox(width: 6), Text("Save")],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BtnGhost(onPressed: () => setState(() => _adding = false), child: const Text("Cancel")),
                    ],
                  ),
                ],
              ),
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
                          IconButton(
                            onPressed: () => _remove(m.id),
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
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

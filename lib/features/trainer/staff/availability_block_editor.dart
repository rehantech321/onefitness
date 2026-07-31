import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";

const _dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const _hourSlots = [420, 480, 540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200]; // 7am-8pm, hourly

/// A simplified stand-in for TrainerForm.jsx's 3-tier BlockEditor: pick a
/// session type + discipline, then toggle hourly slots per weekday.
class AvailabilityBlockEditor extends StatefulWidget {
  const AvailabilityBlockEditor({super.key, required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final ValueChanged<AvailabilityBlock> onSave;

  @override
  State<AvailabilityBlockEditor> createState() => _AvailabilityBlockEditorState();
}

class _AvailabilityBlockEditorState extends State<AvailabilityBlockEditor> {
  String _sessionType = "semi-private";
  String _discipline = "personal-training";
  final Map<int, Set<int>> _byDay = {};

  void _toggle(int day, int slot) {
    setState(() {
      final set = _byDay.putIfAbsent(day, () => {});
      set.contains(slot) ? set.remove(slot) : set.add(slot);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "Availability Block"),
          const SizedBox(height: 12),
          const Text("SESSION TYPE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: kSessionTypeLabels.entries.map((e) {
              final selected = _sessionType == e.key;
              return InkWell(
                onTap: () => setState(() => _sessionType = e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(e.value, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          const Text("DISCIPLINE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: kDisciplineLabels.entries.map((e) {
              final selected = _discipline == e.key;
              return InkWell(
                onTap: () => setState(() => _discipline = e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(e.value, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text("WEEKLY SLOTS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          for (var day = 0; day < 7; day++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 36, child: Padding(padding: const EdgeInsets.only(top: 7), child: Text(_dayLabels[day], style: const TextStyle(fontSize: 11, color: AppColors.mute)))),
                  Expanded(
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: _hourSlots.map((slot) {
                        final on = _byDay[day]?.contains(slot) ?? false;
                        return InkWell(
                          onTap: () => _toggle(day, slot),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                            decoration: BoxDecoration(color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: on ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(6)),
                            child: Text(fmtSlot(slot), style: TextStyle(fontSize: 10, color: on ? AppColors.gold : AppColors.mute)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          BtnGold(
            full: true,
            onPressed: () => widget.onSave(AvailabilityBlock(sessionType: _sessionType, discipline: _discipline, byDay: {for (final e in _byDay.entries) if (e.value.isNotEmpty) e.key: e.value.toList()..sort()})),
            child: const Text("Save block"),
          ),
        ],
      ),
    );
  }
}

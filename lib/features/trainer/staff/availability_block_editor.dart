import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";

// Mirrors schedulingHelpers.js SESSION_WINDOWS/SESSION_LEN/slotsForType —
// each session type's bookable windows (minutes from midnight), walked in
// 30-min steps and filtered down to on-the-hour or on-the-half-hour slots.
const _sessionWindows = {
  "semi-private": [[360, 780], [900, 1200]],
  "one-on-one": [[360, 1320]],
  "large-group": [[360, 1320]],
  "assessment-call": [[360, 1320]],
  "assessment-in-person": [[360, 1320]],
};
const _sessionLen = 60;

List<int> _slotsForType(String sessionType, String interval) {
  final out = <int>[];
  for (final window in _sessionWindows[sessionType] ?? const <List<int>>[]) {
    final s = window[0], e = window[1];
    for (var t = s; t + _sessionLen <= e; t += 30) {
      final onHour = t % 60 == 0;
      final onHalf = t % 60 == 30;
      if (interval == "half" && onHalf) out.add(t);
      if (interval != "half" && onHour) out.add(t);
    }
  }
  return out;
}

// Mon(1)..Sat(6) — mirrors WEEKDAYS in schedulingHelpers.js. Sunday is
// always closed, so it's never offered here.
const _weekdayOrder = [1, 2, 3, 4, 5, 6];
const _weekdayShort = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"};

/// Mirrors TrainerForm.jsx's `BlockEditor` — pick a discipline, select the
/// day(s) that share a schedule, then tap times to apply to all of them at
/// once (tri-state on/partial/off).
class AvailabilityBlockEditor extends StatefulWidget {
  const AvailabilityBlockEditor({
    super.key,
    required this.sessionType,
    required this.disciplineOptions,
    this.initial,
    this.isLargeGroup = false,
    required this.onCancel,
    required this.onSave,
  });

  final String sessionType;
  final List<String> disciplineOptions;
  final AvailabilityBlock? initial;
  final bool isLargeGroup;
  final VoidCallback onCancel;
  final ValueChanged<AvailabilityBlock> onSave;

  @override
  State<AvailabilityBlockEditor> createState() => _AvailabilityBlockEditorState();
}

class _AvailabilityBlockEditorState extends State<AvailabilityBlockEditor> {
  late String? _discipline = widget.initial?.discipline ?? (widget.disciplineOptions.length == 1 ? widget.disciplineOptions.first : null);
  late final Map<int, List<int>> _byDay = {for (final e in (widget.initial?.byDay ?? const {}).entries) e.key: [...e.value]};
  final Set<int> _selectedDays = {};
  String _interval = "hour";
  String? _err;

  List<int> _daySlots(int d) => _byDay[d] ?? const [];

  void _toggleDay(int d) => setState(() => _selectedDays.contains(d) ? _selectedDays.remove(d) : _selectedDays.add(d));
  void _selectAllDays() => setState(() => _selectedDays.addAll(_weekdayOrder));
  void _clearDaySelection() => setState(_selectedDays.clear);

  // "on" only if every selected day already has this slot; "partial" if
  // some but not all do; tapping a slot turns it on/off for ALL selected
  // days at once — that's how you make Mon/Wed/Fri match.
  String _slotState(int s) {
    if (_selectedDays.isEmpty) return "off";
    final have = _selectedDays.where((d) => _daySlots(d).contains(s)).length;
    if (have == _selectedDays.length) return "on";
    if (have > 0) return "partial";
    return "off";
  }

  void _toggleSlot(int s) {
    final turningOn = _slotState(s) != "on";
    setState(() {
      for (final d in _selectedDays) {
        final cur = [..._daySlots(d)];
        if (turningOn) {
          if (!cur.contains(s)) cur.add(s);
        } else {
          cur.remove(s);
        }
        _byDay[d] = cur;
      }
    });
  }

  void _clearSelectedDaysTimes() => setState(() {
        for (final d in _selectedDays) {
          _byDay[d] = [];
        }
      });

  void _save() {
    if (_discipline == null) {
      setState(() => _err = "Choose a discipline for this block.");
      return;
    }
    final byDay = {
      for (final e in _byDay.entries)
        if (e.value.isNotEmpty) e.key: (e.value..sort()),
    };
    widget.onSave(AvailabilityBlock(sessionType: widget.sessionType, discipline: _discipline!, byDay: byDay));
  }

  @override
  Widget build(BuildContext context) {
    final slots = _discipline != null ? _slotsForType(widget.sessionType, _interval) : const <int>[];
    final amSlots = slots.where((s) => s < 720).toList();
    final pmSlots = slots.where((s) => s >= 720).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "${sessionTypeLabel(widget.sessionType)} — Availability"),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Discipline *",
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.disciplineOptions.map((d) {
                final on = _discipline == d;
                return InkWell(
                  onTap: () => setState(() {
                    _discipline = d;
                    _err = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: on ? AppColors.gold : AppColors.line),
                      color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                    ),
                    child: Text(disciplineLabel(d), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.gold : AppColors.mute)),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_discipline != null) ...[
            const SizedBox(height: 14),
            const Text("1. Select the days that share a schedule (e.g. Mon, Wed, Fri together)", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: _weekdayOrder.map((d) {
                final has = _daySlots(d).isNotEmpty;
                final sel = _selectedDays.contains(d);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () => _toggleDay(d),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? AppColors.gold : AppColors.line),
                          color: sel ? AppColors.gold.withValues(alpha: 0.18) : AppColors.bg,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(_weekdayShort[d]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? AppColors.gold : (has ? AppColors.txt : AppColors.mute))),
                            if (has)
                              Positioned(top: -4, right: -6, child: Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.gold))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniBtn(label: "Select all days", onTap: _selectAllDays),
                if (_selectedDays.isNotEmpty) ...[const SizedBox(width: 8), _MiniBtn(label: "Deselect", onTap: _clearDaySelection)],
              ],
            ),
            const SizedBox(height: 14),
            if (_selectedDays.isEmpty)
              const Text("Select one or more days above, then tap their times below.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic))
            else ...[
              Text(
                "2. Tap times for ${_selectedDays.toList().map((d) => _weekdayShort[d]).join('/')}",
                style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (widget.isLargeGroup)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text("Large Group classes always start on the hour · 1 hr · capacity 15", style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _IntervalToggle(label: "On the hour", selected: _interval != "half", onTap: () => setState(() => _interval = "hour")),
                        _IntervalToggle(label: "Every half hour", selected: _interval == "half", onTap: () => setState(() => _interval = "half")),
                      ],
                    ),
                  ),
                ),
              if (amSlots.isNotEmpty) _SlotGroup(label: "AM", slots: amSlots, stateOf: _slotState, onTap: _toggleSlot),
              if (pmSlots.isNotEmpty) _SlotGroup(label: "PM", slots: pmSlots, stateOf: _slotState, onTap: _toggleSlot),
              const SizedBox(height: 4),
              _MiniBtn(label: "Clear times for selected days", onTap: _clearSelectedDaysTimes),
            ],
          ],
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _save,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.check, size: 15), SizedBox(width: 6), Text("Save block")]),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
        ],
      ),
    );
  }
}

class _SlotGroup extends StatelessWidget {
  const _SlotGroup({required this.label, required this.slots, required this.stateOf, required this.onTap});
  final String label;
  final List<int> slots;
  final String Function(int) stateOf;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: slots.map((s) {
              final st = stateOf(s);
              final on = st == "on";
              final partial = st == "partial";
              return InkWell(
                onTap: () => onTap(s),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? AppColors.gold : (partial ? AppColors.goldDim : AppColors.line)),
                    color: on ? AppColors.gold.withValues(alpha: 0.18) : (partial ? AppColors.gold.withValues(alpha: 0.06) : AppColors.card),
                  ),
                  child: Text(fmtSlotShort(s), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? AppColors.gold : (partial ? AppColors.txt : AppColors.mute))),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _IntervalToggle extends StatelessWidget {
  const _IntervalToggle({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: selected ? AppColors.gold : Colors.transparent),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute)),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.line)),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

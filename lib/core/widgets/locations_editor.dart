import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../../data/models/trainer.dart";
import "app_buttons.dart";
import "app_text_field.dart";

const _kHqLocationId = "onefitness-hq";
const _kHqLocation = TrainerLocation(
  id: _kHqLocationId,
  name: "ONE Fitness",
  address: "11300 Magnolia Blvd., North Hollywood, CA 91601",
  hint: "Free parking in the corner plaza, plus free parking on both sides of the street. ONE Fitness is located in the corner unit of the plaza.",
);

/// Mirrors StaffManager.jsx's `LocationsEditor` — a trainer's `locations`
/// list: add/edit/remove, plus a one-tap "+ONE Fitness" quick-add for the
/// gym's own HQ location (DEFAULT_LOCATION in domain.js).
class LocationsEditor extends StatefulWidget {
  const LocationsEditor({super.key, required this.value, required this.onChange});

  final List<TrainerLocation> value;
  final ValueChanged<List<TrainerLocation>> onChange;

  @override
  State<LocationsEditor> createState() => _LocationsEditorState();
}

class _LocationsEditorState extends State<LocationsEditor> {
  String? _editingId; // "new" | an existing location's id | null
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _hint = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _hint.dispose();
    super.dispose();
  }

  void _startNew() {
    _name.clear();
    _address.clear();
    _hint.clear();
    setState(() => _editingId = "new");
  }

  void _startEdit(TrainerLocation loc) {
    _name.text = loc.name;
    _address.text = loc.address ?? "";
    _hint.text = loc.hint ?? "";
    setState(() => _editingId = loc.id);
  }

  void _addHq() => widget.onChange([...widget.value, _kHqLocation]);

  void _remove(String id) => widget.onChange(widget.value.where((l) => l.id != id).toList());

  void _save() {
    final name = _name.text.trim();
    final address = _address.text.trim();
    if (name.isEmpty || address.isEmpty) return;
    final hint = _hint.text.trim();
    if (_editingId == "new") {
      widget.onChange([
        ...widget.value,
        TrainerLocation(id: "loc-${DateTime.now().microsecondsSinceEpoch}", name: name, address: address, hint: hint.isEmpty ? null : hint),
      ]);
    } else {
      widget.onChange(widget.value
          .map((l) => l.id == _editingId ? TrainerLocation(id: l.id, name: name, address: address, hint: hint.isEmpty ? null : hint) : l)
          .toList());
    }
    setState(() => _editingId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_editingId != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldLabeled(label: "Gym / location name *", child: AppField(controller: _name, placeholder: "e.g. Iron Athletics")),
            const SizedBox(height: 8),
            FieldLabeled(label: "Address *", child: AppField(controller: _address, placeholder: "Street, City, State ZIP")),
            const SizedBox(height: 8),
            FieldLabeled(
              label: "Arrival / parking / suite hints",
              child: AppField(controller: _hint, placeholder: "Parking, suite number, how to find the entrance…", minLines: 3, maxLines: 5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BtnGold(
                    onPressed: _save,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(LucideIcons.check, size: 14), SizedBox(width: 6), Text("Save location")],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BtnGhost(onPressed: () => setState(() => _editingId = null), child: const Text("Cancel")),
              ],
            ),
          ],
        ),
      );
    }

    final hasHq = widget.value.any((l) => l.id == _kHqLocationId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.value.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text("No locations yet.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic))),
        ...widget.value.map((loc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.mapPin, size: 13, color: AppColors.gold),
                              const SizedBox(width: 6),
                              Expanded(child: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                            ],
                          ),
                          if ((loc.address ?? "").isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 3), child: Text(loc.address!, style: const TextStyle(fontSize: 12, color: AppColors.mute))),
                          if ((loc.hint ?? "").isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 5), child: Text(loc.hint!, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic, height: 1.4))),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => _startEdit(loc), icon: const Icon(LucideIcons.pencil, size: 14, color: AppColors.mute), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
                    IconButton(onPressed: () => _remove(loc.id), icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
                  ],
                ),
              ),
            )),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!hasHq)
              OutlinedButton(
                onPressed: _addHq,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.txt, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                child: const Text("+ ONE Fitness", style: TextStyle(fontSize: 12)),
              ),
            OutlinedButton(
              onPressed: _startNew,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.txt, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              child: const Text("+ Add location", style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

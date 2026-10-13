import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../utils/gym_location_link.dart";
import "../utils/nearest_location.dart";
import "../../data/providers/platform_settings_provider.dart";
import "../../data/models/trainer.dart";
import "address_fields.dart";
import "app_buttons.dart";
import "app_text_field.dart";

/// Mirrors StaffManager.jsx's `LocationsEditor` — a trainer's `locations`
/// list: add/edit/remove, plus a one-tap "+ONE Fitness" quick-add for the
/// gym's own HQ location (DEFAULT_LOCATION in domain.js).
class LocationsEditor extends ConsumerStatefulWidget {
  const LocationsEditor({super.key, required this.value, required this.onChange});

  final List<TrainerLocation> value;
  final ValueChanged<List<TrainerLocation>> onChange;

  @override
  ConsumerState<LocationsEditor> createState() => _LocationsEditorState();
}

class _LocationsEditorState extends ConsumerState<LocationsEditor> {
  String? _editingId; // "new" | an existing location's id | null
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _hint = TextEditingController();

  /// Where the pin landed for the location being edited. Kept so the
  /// coordinates survive the save — a location with no pin can be shown to
  /// a client but never measured, so no distance is ever offered for
  /// sessions run from it.
  double? _lat;
  double? _lng;
  bool _saving = false;

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
    _lat = null;
    _lng = null;
    setState(() => _editingId = "new");
  }

  void _startEdit(TrainerLocation loc) {
    _name.text = loc.name;
    _address.text = loc.address ?? "";
    _hint.text = loc.hint ?? "";
    _lat = loc.lat;
    _lng = loc.lng;
    setState(() => _editingId = loc.id);
  }

  /// Adds the gym's own location, taken from Customize Platform rather
  /// than from a constant in this file. The entry keeps a fixed id so its
  /// details can be re-read from settings every time it's shown — change
  /// the address in Customize Platform and every coach's follows.
  void _addGym() => widget.onChange([
        ...widget.value,
        gymLocationEntry(ref.read(platformSettingsProvider)),
      ]);

  void _remove(String id) => widget.onChange(widget.value.where((l) => l.id != id).toList());

  Future<void> _save() async {
    final name = _name.text.trim();
    final address = _address.text.trim();
    if (name.isEmpty || address.isEmpty || _saving) return;
    final hint = _hint.text.trim();

    // No pin — either the address was typed rather than picked, or it was
    // edited afterwards. Geocode it rather than saving a location that can
    // never be measured. A failure here is not fatal: the location still
    // saves, it just carries no distance until someone sets it on the map.
    var lat = _lat;
    var lng = _lng;
    if (lat == null || lng == null) {
      setState(() => _saving = true);
      final point = await geocodeAddress(address);
      if (!mounted) return;
      lat = point?.lat;
      lng = point?.lng;
      setState(() => _saving = false);
    }

    if (_editingId == "new") {
      widget.onChange([
        ...widget.value,
        TrainerLocation(
          id: "loc-${DateTime.now().microsecondsSinceEpoch}",
          name: name,
          address: address,
          hint: hint.isEmpty ? null : hint,
          lat: lat,
          lng: lng,
        ),
      ]);
    } else {
      widget.onChange(widget.value
          .map((l) => l.id == _editingId
              ? TrainerLocation(
                  id: l.id,
                  name: name,
                  address: address,
                  hint: hint.isEmpty ? null : hint,
                  lat: lat,
                  lng: lng,
                )
              : l)
          .toList());
    }
    if (mounted) setState(() => _editingId = null);
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
            FieldLabeled(label: "Gym / location name *", child: AppField(kind: FieldKind.name, controller: _name, placeholder: "e.g. Iron Athletics")),
            const SizedBox(height: 8),
            // Keyed per location so switching which one is being edited
            // re-reads the address instead of keeping the last one's fields.
            AddressFields(
              key: ValueKey(_editingId),
              address: _address.text,
              onChanged: (v) {
                // A hand-edited address invalidates the pin that came with
                // the old one; _save re-geocodes rather than keeping a pin
                // that points somewhere else.
                if (v.trim() != _address.text.trim()) {
                  _lat = null;
                  _lng = null;
                }
                _address.text = v;
              },
              onPoint: (lat, lng) {
                _lat = lat;
                _lng = lng;
              },
              showMapButton: true,
            ),
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
                    onPressed: _saving ? null : _save,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check, size: 14),
                        const SizedBox(width: 6),
                        Text(_saving ? "Finding on map…" : "Save location"),
                      ],
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

    final settings = ref.watch(platformSettingsProvider);
    // The gym's entry shows its CURRENT details, not whatever was copied in
    // when it was added.
    final shown = resolveTrainerLocations(widget.value, settings);
    final hasGym = hasGymLocation(widget.value, settings);
    final gymName = settings.defaultLocation?.name ?? settings.locationName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.value.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text("No locations yet.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic))),
        ...shown.map((loc) => Padding(
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
                    if (!isGymLocation(loc))
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
            if (!hasGym && gymName.trim().isNotEmpty)
              OutlinedButton(
                onPressed: _addGym,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.txt, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                child: Text("+ $gymName", style: const TextStyle(fontSize: 12)),
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

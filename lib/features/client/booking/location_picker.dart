import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nearest_location.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// Lets the client choose which of the gym's locations they want to train
/// at, and — if they ask — orders them by how far away they are.
///
/// Location is only read on the "Use my location" tap. Nothing is stored or
/// sent anywhere; the distance is worked out on the device from coordinates
/// already saved against each location.
class LocationPicker extends ConsumerStatefulWidget {
  const LocationPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  /// Null means "any location" — every coach's slots are shown.
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  ConsumerState<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<LocationPicker> {
  /// Distances by location name, once the client has asked for them.
  Map<String, LocationDistance> _distances = {};
  bool _locating = false;
  String? _locationError;

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    final result = await sortByDistance(ref.read(platformSettingsProvider).allLocations);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.error != null) {
        _locationError = nearestErrorMessage(result.error!);
        return;
      }
      _distances = {for (final d in result.sorted) d.location.name: d};
      // Land them on the nearest one — that's the point of asking.
      final nearest = result.nearest;
      if (nearest != null) widget.onSelect(nearest.location.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(platformSettingsProvider);
    final all = settings.allLocations;
    // One location (or none configured) is not a choice worth showing.
    if (all.length < 2) return const SizedBox.shrink();

    // Nearest first once we know, otherwise the gym's own order.
    final ordered = _distances.isEmpty
        ? all
        : (all.toList()
          ..sort((a, b) {
            final da = _distances[a.name]?.metres;
            final db = _distances[b.name]?.metres;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          }));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.mapPin, size: 15, color: AppColors.gold),
              const SizedBox(width: 7),
              const Expanded(
                child: Text("Location", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              if (_distances.isEmpty)
                TextButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  icon: Icon(_locating ? LucideIcons.loader : LucideIcons.navigation, size: 13),
                  label: Text(
                    _locating ? "Finding…" : "Use my location",
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (_locationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _locationError!,
                style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
              ),
            ),
          const SizedBox(height: 8),
          _row(
            label: "Any location",
            sub: "Show every session",
            selected: widget.selected == null,
            onTap: () => widget.onSelect(null),
          ),
          for (final l in ordered)
            _row(
              label: l.name,
              sub: _distances[l.name]?.label ??
                  (l.address.isNotEmpty ? l.address : "Tap to book here"),
              selected: widget.selected == l.name,
              nearest: _distances.isNotEmpty && ordered.first.name == l.name,
              onTap: () => widget.onSelect(l.name),
            ),
        ],
      ),
    );
  }

  Widget _row({
    required String label,
    required String sub,
    required bool selected,
    required VoidCallback onTap,
    bool nearest = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 16,
              color: selected ? AppColors.gold : AppColors.mute,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? AppColors.gold : AppColors.txt,
                          ),
                        ),
                      ),
                      if (nearest) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "Nearest",
                            style: TextStyle(fontSize: 9, color: AppColors.gold, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

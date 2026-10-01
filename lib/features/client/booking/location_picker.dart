import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nearest_location.dart";
import "../../../core/widgets/map_location_picker.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// Lets the client choose which of the gym's locations they want to train
/// at, and — if they ask — orders them by how far away they are.
///
/// Collapsed to one line by default — "My Location: X — Change Location",
/// the same pattern as "Change discipline" — and only opens into the full
/// picker when tapped. Picking closes it again.
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

class _LocationPickerState extends ConsumerState<LocationPicker>
    with WidgetsBindingObserver {
  /// Distances by location name, once the client has asked for them.
  Map<String, LocationDistance> _distances = {};
  bool _locating = false;
  NearestError? _error;

  /// Whether the full picker is open (vs. the one-line summary).
  bool _expanded = false;

  /// Every way of picking ends here: report it, and fold back to one line.
  void _choose(String? name) {
    setState(() => _expanded = false);
    widget.onSelect(name);
  }

  /// Set while the client is away in the device's settings, so coming back
  /// retries automatically instead of making them tap again.
  bool _awaitingSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the settings app — if they turned location on, this picks
    // it up without a second tap, and lands them right back here.
    if (state == AppLifecycleState.resumed && _awaitingSettings) {
      _awaitingSettings = false;
      _useMyLocation();
    }
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final result = await sortByDistance(ref.read(platformSettingsProvider).allLocations);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.error != null) {
        _error = result.error;
        return;
      }
      _distances = {for (final d in result.sorted) d.location.name: d};
    });
    final nearest = result.nearest;
    if (result.error == null && nearest != null) _choose(nearest.location.name);
  }

  Future<void> _openSettings() async {
    final e = _error;
    if (e == null) return;
    _awaitingSettings = true;
    await openSettingsFor(e);
  }

  /// Sets the client's position by dropping a pin instead of using GPS —
  /// for someone who won't grant the permission, or who wants distances
  /// from where they'll be travelling from rather than where they are.
  Future<void> _pickOnMap() async {
    final picked = await showMapLocationPicker(
      context,
      title: "Where are you?",
      subtitle: "Drag the map to set your position. We'll show which gym is closest.",
      initial: null,
    );
    if (picked == null || !mounted) return;
    final all = ref.read(platformSettingsProvider).allLocations;
    final sorted = distancesFrom(picked.lat, picked.lng, all);
    setState(() {
      _error = sorted.isEmpty ? NearestError.noCoords : null;
      _distances = {for (final d in sorted) d.location.name: d};
    });
    if (sorted.isNotEmpty) _choose(sorted.first.location.name);
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
    final nearestName = _distances.isEmpty ? null : ordered.first.name;

    // One line, styled like the discipline row above it. No address here —
    // the open picker shows those.
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            const Text("My Location:", style: TextStyle(fontSize: 13, color: AppColors.mute)),
            Text(widget.selected ?? "Any location",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
            GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: const Text("Change Location",
                  style: TextStyle(fontSize: 11, color: AppColors.mute, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      );
    }

    Widget option(String? value, String label, {String address = "", LocationDistance? distance}) {
      final on = widget.selected == value;
      return InkWell(
        onTap: () => _choose(value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18, color: on ? AppColors.gold : AppColors.mute),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                    if (address.isNotEmpty)
                      Text(address, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.3)),
                  ],
                ),
              ),
              if (distance != null) ...[
                const SizedBox(width: 8),
                Text(
                  distance.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: value == nearestName ? AppColors.gold : AppColors.mute,
                    fontWeight: value == nearestName ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

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
                child: Text("Change Location", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              // Close without changing anything.
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: const Icon(LucideIcons.x, size: 16, color: AppColors.mute),
              ),
            ],
          ),
          const SizedBox(height: 6),

          option(null, "Any location"),
          for (final l in ordered)
            option(l.name, l.name, address: l.address, distance: _distances[l.name]),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.goldDim),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: Icon(_locating ? LucideIcons.loader : LucideIcons.navigation, size: 13),
                  label: Text(
                    _locating ? "Finding…" : "Use my location",
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _pickOnMap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mute,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(LucideIcons.map, size: 13),
                  label: const Text("Pick on map",
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              nearestErrorMessage(_error!),
              style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
            ),
            // Only offered when settings can actually fix it — sending
            // someone to Settings for a missing address would waste a trip.
            if (settingsTargetFor(_error!) != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: _openSettings,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(LucideIcons.settings, size: 13),
                  label: Text(
                    settingsTargetFor(_error!) == SettingsTarget.device
                        ? "Open location settings"
                        : "Open app settings",
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

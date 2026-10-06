import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../utils/nearest_location.dart";
import "widgets.dart";

/// A point chosen on the map, with the address it resolved to when one
/// could be found.
class PickedPoint {
  const PickedPoint({required this.lat, required this.lng, this.place});
  final double lat;
  final double lng;

  /// Street, city, state and ZIP at the point — null when the geocoder
  /// couldn't name it.
  final AddressParts? place;

  /// The same, as the one-line address the settings store.
  String? get address => place?.compose();
}

/// Search for a place, drop a pin, or use where you are to set a location —
/// used by the owner to place a gym exactly where it is (when an address won't geocode, or the geocoded point lands
/// on the wrong side of the block), and by a client to say where they are
/// without granting location permission.
///
/// OpenStreetMap tiles: no API key, no billing account, and no per-platform
/// setup, which for one picker beats wiring up a paid maps SDK. The crosshair
/// is fixed to the centre and the map moves under it, which is steadier on a
/// phone than dragging a pin with a thumb that covers it.
Future<PickedPoint?> showMapLocationPicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  PickedPoint? initial,
}) {
  return showModalBottomSheet<PickedPoint>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MapPickerSheet(title: title, subtitle: subtitle, initial: initial),
  );
}

class _MapPickerSheet extends StatefulWidget {
  const _MapPickerSheet({required this.title, this.subtitle, this.initial});
  final String title;
  final String? subtitle;
  final PickedPoint? initial;

  @override
  State<_MapPickerSheet> createState() => _MapPickerSheetState();
}

class _MapPickerSheetState extends State<_MapPickerSheet> {
  final _map = MapController();

  /// Los Angeles — only ever seen when there's no starting point and the
  /// device won't give one, and the gym is in North Hollywood.
  static const _fallback = LatLng(34.1706, -118.3768);

  late LatLng _centre = widget.initial != null
      ? LatLng(widget.initial!.lat, widget.initial!.lng)
      : _fallback;

  bool _locating = false;
  String? _note;

  final _search = TextEditingController();
  bool _searching = false;

  /// What's under the pin right now, looked up a moment after the map
  /// stops moving so the owner sees the city/state/ZIP before confirming.
  AddressParts? _place;
  LatLng? _placeFor;
  bool _lookingUp = false;
  Timer? _lookupDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _scheduleLookup();
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleLookup() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 600), _lookup);
  }

  Future<void> _lookup() async {
    final at = _centre;
    if (_placeFor == at) return;
    if (mounted) setState(() => _lookingUp = true);
    final place = await placeFor(at.latitude, at.longitude);
    // The map may have moved on while this was in flight.
    if (!mounted || at != _centre) return;
    setState(() {
      _place = place;
      _placeFor = at;
      _lookingUp = false;
    });
  }

  void _moveTo(LatLng to) {
    setState(() => _centre = to);
    _map.move(to, 16);
    _scheduleLookup();
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _note = null;
    });
    final hit = await geocodeAddress(query);
    if (!mounted) return;
    setState(() => _searching = false);
    if (hit == null) {
      setState(() => _note = "Couldn't find \"$query\". Try adding the city or ZIP.");
      return;
    }
    _moveTo(LatLng(hit.lat, hit.lng));
  }

  Future<void> _goToMyLocation() async {
    setState(() {
      _locating = true;
      _note = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _PickerNote("Location is switched off on this device.");
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw const _PickerNote("We don't have permission to use your location.");
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _locating = false);
      _moveTo(LatLng(pos.latitude, pos.longitude));
    } on _PickerNote catch (e) {
      if (mounted) setState(() { _locating = false; _note = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _note = "Couldn't get your location just now.";
        });
      }
    }
  }

  Future<void> _confirm() async {
    // Reverse-geocoding is a nicety: the point is what matters, and an
    // address that won't resolve must not block confirming.
    _lookupDebounce?.cancel();
    final at = _centre;
    final place = _placeFor == at ? _place : await placeFor(at.latitude, at.longitude);
    if (!mounted) return;
    Navigator.of(context).pop(PickedPoint(
      lat: at.latitude,
      lng: at.longitude,
      place: place,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.8;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(widget.subtitle!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.mute, height: 1.4)),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20, color: AppColors.mute),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(
              children: [
                Expanded(
                  child: AppField(
                    kind: FieldKind.address,
                    controller: _search,
                    placeholder: "Search an address or place",
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _searching ? null : _runSearch,
                  icon: Icon(_searching ? LucideIcons.loader : LucideIcons.search, size: 18, color: AppColors.gold),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _centre,
                    initialZoom: widget.initial != null ? 16 : 11,
                    onPositionChanged: (pos, _) {
                      _centre = pos.center;
                      _scheduleLookup();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      // OSM's tile policy requires identifying the client.
                      userAgentPackageName: "com.onefitness.app",
                    ),
                  ],
                ),
                // Fixed crosshair: the map moves under it, so the target is
                // never hidden under a finger.
                IgnorePointer(
                  child: Padding(
                    // Lifts the pin so its point, not its middle, marks the
                    // centre of the map.
                    padding: const EdgeInsets.only(bottom: 34),
                    child: Icon(LucideIcons.mapPin,
                        size: 36, color: AppColors.gold, shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                    ]),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: "map_my_location",
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.gold,
                    onPressed: _locating ? null : _goToMyLocation,
                    child: Icon(_locating ? LucideIcons.loader : LucideIcons.crosshair, size: 18),
                  ),
                ),
              ],
            ),
          ),
          // What "Use this spot" will fill in, so the city, state and ZIP
          // can be checked before confirming.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.mapPin, size: 14, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _lookingUp
                        ? "Finding address…"
                        : (_place?.compose().isNotEmpty ?? false)
                            ? _place!.compose()
                            : "Move the map to the location, search for it, or use the crosshair.",
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: _place != null && !_lookingUp ? AppColors.txt : AppColors.mute,
                      fontWeight: _place != null && !_lookingUp ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(_note!,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: SafeArea(
              top: false,
              child: BtnGold(
                full: true,
                onPressed: _confirm,
                child: const Text("Use this spot"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carries a human-readable reason out of the location lookup above.
class _PickerNote implements Exception {
  const _PickerNote(this.message);
  final String message;
}

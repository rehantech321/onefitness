import "package:geocoding/geocoding.dart" as geo;
import "package:geolocator/geolocator.dart";
import "../../data/providers/platform_settings_provider.dart";
import "address_utils.dart";

export "address_utils.dart" show AddressParts;

/// Finding the client's nearest gym, and how far away it is.
///
/// Location is only ever read when the client asks for it — there's no
/// background tracking and nothing is stored or sent anywhere. The position
/// is used on the device to sort the gym's locations by distance and then
/// discarded.
///
/// Each location's coordinates are resolved once by geocoding its address
/// and cached on the settings row, so the distance itself needs no network.

/// One location with how far the client is from it.
class LocationDistance {
  const LocationDistance({required this.location, required this.metres});
  final GymLocation location;
  final double metres;

  double get miles => metres / 1609.344;
  double get km => metres / 1000;

  /// "0.4 mi away", "2.3 mi away", "12 mi away" — precision drops as the
  /// number grows, because "12.37 mi" reads as false precision.
  String get label {
    final m = miles;
    if (m < 0.1) return "Less than 0.1 mi away";
    if (m < 10) return "${m.toStringAsFixed(1)} mi away";
    return "${m.round()} mi away";
  }
}

/// Why we couldn't work out a distance, in words a client can act on.
enum NearestError { serviceOff, denied, deniedForever, noCoords, failed }

/// Which settings screen actually fixes each failure — the device's
/// location switch, or this app's own permission. Null when opening
/// settings wouldn't help.
enum SettingsTarget { device, app }

SettingsTarget? settingsTargetFor(NearestError e) {
  switch (e) {
    case NearestError.serviceOff:
      return SettingsTarget.device;
    case NearestError.denied:
    case NearestError.deniedForever:
      return SettingsTarget.app;
    case NearestError.noCoords:
    case NearestError.failed:
      return null;
  }
}

/// Opens the right settings screen for [e]. The client comes back to
/// exactly where they were — the caller retries when the app resumes.
Future<void> openSettingsFor(NearestError e) async {
  switch (settingsTargetFor(e)) {
    case SettingsTarget.device:
      await Geolocator.openLocationSettings();
    case SettingsTarget.app:
      await Geolocator.openAppSettings();
    case null:
      break;
  }
}

String nearestErrorMessage(NearestError e) {
  switch (e) {
    case NearestError.serviceOff:
      return "Location is switched off on this device. Turn it on to see which gym is nearest.";
    case NearestError.denied:
      return "We need permission to use your location to show your nearest gym.";
    case NearestError.deniedForever:
      return "Location is blocked for ONE Fitness. You can allow it in your device Settings.";
    case NearestError.noCoords:
      return "We don't have map coordinates for the gym's locations yet — ask ONE Fitness to add an address for each one.";
    case NearestError.failed:
      return "Couldn't get your location just now. Please try again.";
  }
}

class NearestResult {
  const NearestResult({this.sorted = const [], this.error});
  final List<LocationDistance> sorted;
  final NearestError? error;

  bool get ok => error == null && sorted.isNotEmpty;
  LocationDistance? get nearest => sorted.isEmpty ? null : sorted.first;
}

/// Asks for permission if it hasn't been granted, reads the position once,
/// and returns [locations] sorted nearest first.
///
/// Locations with no coordinates are left out of the ordering rather than
/// being treated as infinitely far away, so a half-configured gym doesn't
/// produce a nonsense list.
Future<NearestResult> sortByDistance(List<GymLocation> locations) async {
  final withCoords = locations.where((l) => l.hasCoords).toList();
  if (withCoords.isEmpty) {
    return const NearestResult(error: NearestError.noCoords);
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    return const NearestResult(error: NearestError.serviceOff);
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    return const NearestResult(error: NearestError.deniedForever);
  }
  if (permission == LocationPermission.denied) {
    return const NearestResult(error: NearestError.denied);
  }

  try {
    // Low accuracy on purpose: a distance in miles doesn't need a precise
    // fix, and a coarse one is faster and less intrusive.
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    final out = withCoords
        .map((l) => LocationDistance(
              location: l,
              metres: Geolocator.distanceBetween(pos.latitude, pos.longitude, l.lat!, l.lng!),
            ))
        .toList()
      ..sort((a, b) => a.metres.compareTo(b.metres));
    return NearestResult(sorted: out);
  } catch (e) {
    return const NearestResult(error: NearestError.failed);
  }
}

/// Distances from an arbitrary point, for a client who set their position
/// on the map instead of using GPS. Same ordering and labelling as
/// [sortByDistance]; locations without coordinates are left out.
List<LocationDistance> distancesFrom(double lat, double lng, List<GymLocation> locations) {
  final out = locations
      .where((l) => l.hasCoords)
      .map((l) => LocationDistance(
            location: l,
            metres: Geolocator.distanceBetween(lat, lng, l.lat!, l.lng!),
          ))
      .toList()
    ..sort((a, b) => a.metres.compareTo(b.metres));
  return out;
}

/// The nearest street address to a point, for showing back what was picked
/// on the map. Null when the platform geocoder can't name it.
Future<String?> addressFor(double lat, double lng) async {
  return (await placeFor(lat, lng))?.compose();
}

/// The street, city, state and ZIP at a point, for filling in the address
/// fields after a map pick. Null when the platform geocoder can't name it.
Future<AddressParts?> placeFor(double lat, double lng) async {
  try {
    final places = await geo.placemarkFromCoordinates(lat, lng);
    if (places.isEmpty) return null;
    final p = places.first;
    String clean(String? v) => (v ?? "").trim();

    // Number + street name when the geocoder splits them out. Otherwise
    // `name`, or the first segment of `street` — on Android that's the
    // whole formatted line ("2422 W Victory Blvd, Burbank, CA …"), which
    // would repeat the city and state.
    var street = [clean(p.subThoroughfare), clean(p.thoroughfare)].where((v) => v.isNotEmpty).join(" ");
    if (clean(p.thoroughfare).isEmpty) {
      final name = clean(p.name);
      street = name.isNotEmpty && name != clean(p.postalCode) && name != clean(p.locality)
          ? name
          : clean(p.street).split(",").first.trim();
    }
    final city = clean(p.locality).isNotEmpty ? clean(p.locality) : clean(p.subLocality);
    final parts = AddressParts(
      street: street,
      city: city,
      state: stateCode(clean(p.administrativeArea)),
      zip: clean(p.postalCode),
    );
    return parts.isEmpty ? null : parts;
  } catch (e) {
    return null;
  }
}

/// Turns an address into coordinates. Returns null when the address is empty
/// or the platform geocoder can't place it — the caller keeps whatever it
/// had rather than wiping a good value with a failed lookup.
Future<({double lat, double lng})?> geocodeAddress(String address) async {
  final query = address.trim();
  if (query.isEmpty) return null;
  try {
    final results = await geo.locationFromAddress(query);
    if (results.isEmpty) return null;
    return (lat: results.first.latitude, lng: results.first.longitude);
  } catch (e) {
    return null;
  }
}

/// Fills in missing coordinates for every location that has an address but
/// no coordinates yet, returning the updated settings — or the same object
/// when nothing needed doing, so the caller can skip a pointless save.
Future<PlatformSettings> withGeocodedLocations(PlatformSettings settings) async {
  var changed = false;
  var next = settings;

  if (settings.locationAddress.trim().isNotEmpty && settings.locationLat == null) {
    final hit = await geocodeAddress(settings.locationAddress);
    if (hit != null) {
      next = next.copyWith(locationLat: hit.lat, locationLng: hit.lng);
      changed = true;
    }
  }

  final updated = <GymLocation>[];
  for (final l in next.locations) {
    if (l.address.trim().isNotEmpty && !l.hasCoords) {
      final hit = await geocodeAddress(l.address);
      if (hit != null) {
        updated.add(l.copyWith(lat: hit.lat, lng: hit.lng));
        changed = true;
        continue;
      }
    }
    updated.add(l);
  }
  if (changed) next = next.copyWith(locations: updated);

  return changed ? next : settings;
}

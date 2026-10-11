import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:geolocator/geolocator.dart";

import "../../data/models/trainer.dart";
import "../../data/providers/platform_settings_provider.dart";
import "../../data/providers/client_providers.dart";
import "booking_location.dart";
import "nearest_location.dart";

/// Everywhere a session can actually happen, from either side.
///
/// The gym's own locations come from Customize Platform; a coach can also
/// set one of their own, which overrides the gym's on their sessions. Those
/// two lived entirely separately: the admin's Location page never showed a
/// coach's, and the booking screen could only measure the gym's — so a
/// session run from a coach's own place sorted last and showed no distance,
/// which is the one case "sessions near me" needed to work.
class SessionPlace {
  const SessionPlace({
    required this.name,
    required this.setBy,
    this.address = "",
    this.hint = "",
    this.lat,
    this.lng,
    this.coachName,
  });

  final String name;
  final String address;
  final String hint;
  final double? lat;
  final double? lng;

  /// "gym" when it came from Customize Platform, "coach" when a coach set
  /// it on their own profile.
  final String setBy;

  /// Who set it, when [setBy] is "coach" — so the admin's Location page can
  /// say whose it is.
  final String? coachName;

  bool get hasCoords => lat != null && lng != null;
  bool get isCoachSet => setBy == "coach";
}

/// Every place, gym-set first, then anything a coach added that the gym
/// doesn't already list.
///
/// Matching is by name, trimmed and case-insensitive: a coach typing "one
/// fitness" for the gym's own "ONE Fitness" is naming the same building, and
/// listing it twice would put the same address in front of a client twice.
List<SessionPlace> allSessionPlaces(PlatformSettings settings, List<Trainer> trainers) {
  final places = <SessionPlace>[
    for (final l in settings.allLocations)
      SessionPlace(
        name: l.name,
        address: l.address,
        hint: l.hint,
        lat: l.lat,
        lng: l.lng,
        setBy: "gym",
      ),
  ];
  final seen = {for (final p in places) p.name.trim().toLowerCase()};

  for (final t in trainers) {
    for (final l in t.locations) {
      final key = l.name.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      places.add(SessionPlace(
        name: l.name,
        address: l.address ?? "",
        hint: l.hint ?? "",
        lat: l.lat,
        lng: l.lng,
        setBy: "coach",
        coachName: t.name,
      ));
    }
  }
  return places;
}

final sessionPlacesProvider = Provider<List<SessionPlace>>((ref) {
  return allSessionPlaces(
    ref.watch(platformSettingsProvider),
    ref.watch(trainersProvider),
  );
});

/// Just the ones a coach added — what the admin's Location page lists so the
/// owner can see where their coaches are actually running sessions.
final coachSetPlacesProvider = Provider<List<SessionPlace>>((ref) {
  return ref.watch(sessionPlacesProvider).where((p) => p.isCoachSet).toList();
});

/// Where to measure a client *from*.
///
/// The device's own position is the honest answer to "how far is this from
/// me", so it's tried first. It needs permission and can be refused or
/// simply unavailable indoors, so the client's own city and state are the
/// fallback — less precise, but it is what they told us their home is, and a
/// rough distance beats none.
///
/// Returns null only when neither is available, in which case distances are
/// left off rather than guessed.
final clientOriginProvider = FutureProvider<({double lat, double lng})?>((ref) async {
  try {
    if (await Geolocator.isLocationServiceEnabled()) {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        return (lat: pos.latitude, lng: pos.longitude);
      }
    }
  } catch (_) {
    // Fall through to the profile place — a refused or failed fix is an
    // ordinary outcome here, not an error worth surfacing.
  }

  // The point the client set for themselves, kept from the last time they
  // used their position or dropped a pin.
  final info = ref.watch(clientInfoProvider);
  if (info.hasHomePoint) return (lat: info.homeLat!, lng: info.homeLng!);

  // Last resort: their city and state. This answers with the centre of the
  // city, so it is the least accurate of the three and deliberately last.
  final place = clientPlaceQuery(info);
  if (place.isEmpty) return null;
  return geocodeAddress(place);
});

/// How far each place is from the client, in metres, keyed by place name.
///
/// Measured from the client themselves rather than from one gym to another,
/// which is what "how far is this session from me" actually means. Places
/// with no coordinates are absent rather than given a made-up distance.
final placeDistancesProvider = Provider<Map<String, double>>((ref) {
  final origin = ref.watch(clientOriginProvider).value;
  if (origin == null) return const {};
  return {
    for (final p in ref.watch(sessionPlacesProvider))
      if (p.hasCoords)
        p.name: Geolocator.distanceBetween(origin.lat, origin.lng, p.lat!, p.lng!),
  };
});

/// "2.4 mi" / "600 ft" — short enough to sit on a slot row.
///
/// Miles, because this gym is in California and its clients think in them.
/// Under a quarter of a mile reads as feet: "0.1 mi" to the gym across the
/// street is technically right and practically useless.
String formatDistance(double metres) {
  final miles = metres / 1609.344;
  if (miles < 0.25) {
    final feet = (metres * 3.28084).round();
    final rounded = feet < 100 ? feet : (feet / 50).round() * 50;
    return "$rounded ft";
  }
  if (miles < 10) return "${miles.toStringAsFixed(1)} mi";
  return "${miles.round()} mi";
}

import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../data/models/client_info.dart";
import "../../data/providers/platform_settings_provider.dart";
import "nearest_location.dart";

/// The gym location nearest a free-text profile city ("Miami, FL"), by
/// name. Null while the geocoder hasn't answered, when it can't place the
/// city, or when no location has coordinates to compare against.
///
/// Keyed on the city text, so editing the city in Profile Settings
/// naturally re-resolves it, and repeat visits reuse the one lookup.
final nearestToCityProvider = FutureProvider.family<String?, String>((ref, city) async {
  final all = ref.watch(platformSettingsProvider.select((s) => s.allLocations));
  final point = await geocodeAddress(city);
  if (point == null) return null;
  final sorted = distancesFrom(point.lat, point.lng, all);
  return sorted.isEmpty ? null : sorted.first.location.name;
});

/// Where this client's booking screen starts, as a location name — or null
/// for "Any location". In order:
///   1. what they last picked via "Change Location" (if it still exists);
///   2. the gym nearest their profile city;
///   3. the gym's default location.
/// A gym with fewer than two locations has nothing to choose between, so
/// it's always null there (every session shows).
String? effectiveBookingLocation(WidgetRef ref, ClientInfo info) {
  final settings = ref.watch(platformSettingsProvider);
  final all = settings.allLocations;
  if (all.length < 2) return null;
  final names = {for (final l in all) l.name};

  final chosen = info.bookingLocation;
  if (chosen == kAnyLocation) return null;
  if (chosen != null && names.contains(chosen)) return chosen;
  return _homeLocation(ref, info, settings);
}

/// Steps 2–3 of [effectiveBookingLocation]: nearest to the profile city,
/// else the gym default.
String? _homeLocation(WidgetRef ref, ClientInfo info, PlatformSettings settings) {
  final names = {for (final l in settings.allLocations) l.name};
  final city = info.city?.trim() ?? "";
  if (city.isNotEmpty) {
    final nearest = ref.watch(nearestToCityProvider(city)).value;
    if (nearest != null && names.contains(nearest)) return nearest;
  }
  return settings.defaultLocation?.name;
}

/// Metres from the client's current booking location (or, on "Any
/// location", their home one) to every other location with coordinates —
/// so sessions can be listed nearest first. Empty when there's nothing to
/// measure from.
Map<String, double> bookingLocationDistances(WidgetRef ref, ClientInfo info) {
  final settings = ref.watch(platformSettingsProvider);
  final all = settings.allLocations;
  if (all.length < 2) return const {};
  final fromName = effectiveBookingLocation(ref, info) ?? _homeLocation(ref, info, settings);
  final from = all.where((l) => l.name == fromName && l.hasCoords);
  if (from.isEmpty) return const {};
  return {
    for (final d in distancesFrom(from.first.lat!, from.first.lng!, all)) d.location.name: d.metres,
  };
}

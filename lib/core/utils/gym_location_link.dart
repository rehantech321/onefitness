import "../../data/models/trainer.dart";
import "../../data/providers/platform_settings_provider.dart";

/// Keeping a coach's "ONE Fitness" entry in step with Customize Platform.
///
/// A coach's locations are stored as a copy — name, address, hint — on
/// their own profile. That is right for a coach who trains somewhere of
/// their own, and wrong for the gym's own site: the quick-add used to
/// insert a hardcoded address and parking note written into the app's
/// source. Whatever the owner set in Customize Platform → Location, every
/// coach who tapped it got that frozen text, and changing the gym's address
/// afterwards changed nothing for any of them. It carried no coordinates
/// either, so no client was ever shown a distance to it.
///
/// So the entry is *linked* rather than copied: it keeps a fixed id, and
/// its details are read back from the gym's settings every time it is used.
/// Edit the address in Customize Platform and every coach's copy follows,
/// because none of them is really a copy.
const kGymLocationId = "onefitness-hq";

/// True for the entry that stands for the gym's own location.
bool isGymLocation(TrainerLocation l) => l.id == kGymLocationId;

/// The entry to store on a coach's profile when they pick the gym's
/// location. Only the id carries meaning; the rest is filled in so an older
/// app build, or anything reading the row directly, still sees something
/// sensible rather than a bare id.
TrainerLocation gymLocationEntry(PlatformSettings settings) {
  final gym = settings.defaultLocation;
  return TrainerLocation(
    id: kGymLocationId,
    name: gym?.name ?? settings.locationName,
    address: gym?.address ?? settings.locationAddress,
    hint: gym?.hint ?? settings.locationHint,
    lat: gym?.lat ?? settings.locationLat,
    lng: gym?.lng ?? settings.locationLng,
  );
}

/// One of a coach's locations, with the gym's own details refreshed from
/// settings. Anything they set up themselves is returned untouched — it is
/// theirs, and the gym's settings have nothing to say about it.
TrainerLocation resolveTrainerLocation(TrainerLocation l, PlatformSettings settings) =>
    isGymLocation(l) ? gymLocationEntry(settings) : l;

/// A coach's whole list, resolved.
List<TrainerLocation> resolveTrainerLocations(
  List<TrainerLocation> locations,
  PlatformSettings settings,
) =>
    [for (final l in locations) resolveTrainerLocation(l, settings)];

/// Whether this coach already holds the gym's location, so the quick-add
/// isn't offered twice.
///
/// Matches on the id first, then on the name, because a coach who typed
/// "ONE Fitness" by hand before this existed has an entry that means the
/// same thing and should not end up with two.
bool hasGymLocation(List<TrainerLocation> locations, PlatformSettings settings) {
  final gymName = (settings.defaultLocation?.name ?? settings.locationName).trim().toLowerCase();
  for (final l in locations) {
    if (isGymLocation(l)) return true;
    if (gymName.isNotEmpty && l.name.trim().toLowerCase() == gymName) return true;
  }
  return false;
}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/gym_location_link.dart";
import "package:onefitness/data/models/trainer.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";

/// A coach picking "the gym's location" used to copy a hardcoded address
/// and parking note written into the app's source — not whatever the owner
/// had set in Customize Platform. Changing the gym's address afterwards
/// changed nothing for any coach who had already added it, and the copy
/// carried no coordinates, so no client was ever shown a distance to it.
///
/// The entry is now linked by a fixed id and its details re-read from
/// settings, so these tests are about one thing: the gym's own location
/// always reflects Customize Platform, and a coach's own location never
/// gets overwritten by it.
void main() {
  PlatformSettings settings({
    String name = "ONE Fitness",
    String address = "11300 Magnolia Blvd., North Hollywood, CA 91601",
    String hint = "Free parking in the corner plaza.",
    double? lat = 34.1680,
    double? lng = -118.3780,
  }) =>
      PlatformSettings(
        locationName: name,
        locationAddress: address,
        locationHint: hint,
        locationLat: lat,
        locationLng: lng,
      );

  TrainerLocation gymEntry(PlatformSettings s) => gymLocationEntry(s);

  const ownLocation = TrainerLocation(
    id: "loc-123",
    name: "Iron Athletics",
    address: "9 Oak Ave",
    hint: "Side door",
    lat: 34.05,
    lng: -118.25,
  );

  group("the gym's entry follows Customize Platform", () {
    test("it carries the gym's current name, address and hint", () {
      final entry = gymEntry(settings());
      expect(entry.name, "ONE Fitness");
      expect(entry.address, "11300 Magnolia Blvd., North Hollywood, CA 91601");
      expect(entry.hint, "Free parking in the corner plaza.");
    });

    test("it carries the gym's map pin, so distances work", () {
      // The old hardcoded copy had none, which is why sessions at the gym
      // never showed a client how far away it was.
      final entry = gymEntry(settings());
      expect(entry.hasCoords, isTrue);
      expect(entry.lat, closeTo(34.1680, 0.0001));
    });

    test("changing the address in settings changes what a coach shows", () {
      // The whole point: an entry added months ago reflects today's
      // settings, because it was never really a copy.
      final stale = gymEntry(settings());
      final afterMove = settings(
        name: "ONE Fitness Burbank",
        address: "500 New Street, Burbank, CA",
        hint: "Rear lot",
        lat: 34.1808,
        lng: -118.3090,
      );
      final resolved = resolveTrainerLocation(stale, afterMove);
      expect(resolved.name, "ONE Fitness Burbank");
      expect(resolved.address, "500 New Street, Burbank, CA");
      expect(resolved.hint, "Rear lot");
      expect(resolved.lat, closeTo(34.1808, 0.0001));
    });

    test("a renamed gym is renamed everywhere at once", () {
      final entry = gymEntry(settings());
      final renamed = resolveTrainerLocation(entry, settings(name: "ONE Fitness NoHo"));
      expect(renamed.name, "ONE Fitness NoHo");
      // Same entry, still the gym's.
      expect(isGymLocation(renamed), isTrue);
    });

    test("it keeps the fixed id that marks it as the gym's", () {
      expect(gymEntry(settings()).id, kGymLocationId);
      expect(isGymLocation(gymEntry(settings())), isTrue);
    });
  });

  group("a coach's own location is left alone", () {
    test("it is not the gym's", () {
      expect(isGymLocation(ownLocation), isFalse);
    });

    test("resolving returns it untouched", () {
      final resolved = resolveTrainerLocation(ownLocation, settings());
      expect(resolved.name, "Iron Athletics");
      expect(resolved.address, "9 Oak Ave");
      expect(resolved.lat, 34.05);
    });

    test("the gym's settings don't overwrite it even after the gym moves", () {
      final resolved = resolveTrainerLocation(
        ownLocation,
        settings(name: "Somewhere Else", address: "Another Road"),
      );
      expect(resolved.name, "Iron Athletics");
      expect(resolved.address, "9 Oak Ave");
    });

    test("a whole list resolves the gym's and keeps the rest", () {
      final list = resolveTrainerLocations(
        [gymEntry(settings()), ownLocation],
        settings(name: "ONE Fitness Burbank", address: "500 New Street"),
      );
      expect(list.map((l) => l.name), ["ONE Fitness Burbank", "Iron Athletics"]);
    });
  });

  group("not offering the gym twice", () {
    test("a coach already linked to it isn't offered it again", () {
      expect(hasGymLocation([gymEntry(settings())], settings()), isTrue);
    });

    test("a coach with only their own location is offered it", () {
      expect(hasGymLocation([ownLocation], settings()), isFalse);
    });

    test("someone who typed the gym's name by hand counts as having it", () {
      // Predates the link. Offering the shortcut would leave them holding
      // two entries meaning the same building.
      const typed = TrainerLocation(id: "loc-9", name: "ONE Fitness");
      expect(hasGymLocation([typed], settings()), isTrue);
    });

    test("matching the typed name ignores case and spacing", () {
      const typed = TrainerLocation(id: "loc-9", name: "  one fitness ");
      expect(hasGymLocation([typed], settings()), isTrue);
    });

    test("a similarly-named but different gym does not count", () {
      const other = TrainerLocation(id: "loc-9", name: "ONE Fitness Burbank");
      expect(hasGymLocation([other], settings()), isFalse);
    });

    test("an empty list has no gym location", () {
      expect(hasGymLocation(const [], settings()), isFalse);
    });
  });

  group("when the gym hasn't been set up", () {
    test("resolving falls back to blanks rather than throwing", () {
      final bare = settings(name: "", address: "", hint: "", lat: null, lng: null);
      final entry = gymLocationEntry(bare);
      expect(entry.name, "");
      expect(entry.hasCoords, isFalse);
    });

    test("nothing is treated as already having a nameless gym", () {
      final bare = settings(name: "", address: "", hint: "");
      expect(hasGymLocation([ownLocation], bare), isFalse);
    });
  });
}

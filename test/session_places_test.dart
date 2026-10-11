import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/session_places.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/trainer.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";

/// The gym's own locations and the ones coaches set for themselves used to
/// live entirely apart: the admin's Location page never showed a coach's,
/// and the booking screen could only measure the gym's — so a session run
/// from a coach's own place sorted last and showed no distance at all.
void main() {
  PlatformSettings settings({
    String mainName = "ONE Fitness Burbank",
    String mainAddress = "1 Main St, Burbank, CA",
    double? lat = 34.1808,
    double? lng = -118.3090,
    List<GymLocation> extra = const [],
  }) =>
      PlatformSettings(
        locationName: mainName,
        locationAddress: mainAddress,
        locationLat: lat,
        locationLng: lng,
        locations: extra,
      );

  Trainer coach({
    String id = "t1",
    String name = "Jess",
    List<TrainerLocation> locations = const [],
  }) =>
      Trainer(id: id, name: name, locations: locations);

  group("gathering every place a session can happen", () {
    test("the gym's own location is included", () {
      final places = allSessionPlaces(settings(), const []);
      expect(places.map((p) => p.name), ["ONE Fitness Burbank"]);
      expect(places.first.setBy, "gym");
    });

    test("a coach's own location is included, and marked as theirs", () {
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "Iron Athletics", address: "9 Oak Ave")])],
      );
      expect(places.map((p) => p.name), ["ONE Fitness Burbank", "Iron Athletics"]);
      final theirs = places.last;
      expect(theirs.setBy, "coach");
      expect(theirs.coachName, "Jess");
      expect(theirs.isCoachSet, isTrue);
    });

    test("a coach naming the gym's own location doesn't duplicate it", () {
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "ONE Fitness Burbank")])],
      );
      expect(places.length, 1);
      // The gym's entry wins, so the address and pin stay the gym's.
      expect(places.single.setBy, "gym");
    });

    test("matching ignores case and stray spaces", () {
      // "one fitness burbank " is the same building.
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "  one fitness burbank ")])],
      );
      expect(places.length, 1);
    });

    test("two coaches at the same place list it once", () {
      final places = allSessionPlaces(settings(), [
        coach(id: "t1", name: "Jess", locations: const [TrainerLocation(id: "a", name: "Iron Athletics")]),
        coach(id: "t2", name: "Sam", locations: const [TrainerLocation(id: "b", name: "Iron Athletics")]),
      ]);
      expect(places.where((p) => p.name == "Iron Athletics").length, 1);
    });

    test("a blank coach location is skipped rather than listed empty", () {
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "   ")])],
      );
      expect(places.length, 1);
    });

    test("coach locations are still gathered when the gym has set none", () {
      final places = allSessionPlaces(
        settings(mainName: "", mainAddress: ""),
        [coach(locations: const [TrainerLocation(id: "l1", name: "Iron Athletics")])],
      );
      expect(places.map((p) => p.name), ["Iron Athletics"]);
    });
  });

  group("which places can actually be measured", () {
    test("a coach location with a pin can be", () {
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "Iron Athletics", lat: 34.05, lng: -118.25)])],
      );
      expect(places.last.hasCoords, isTrue);
    });

    test("one without a pin cannot, and is not given a made-up one", () {
      final places = allSessionPlaces(
        settings(),
        [coach(locations: const [TrainerLocation(id: "l1", name: "Iron Athletics")])],
      );
      expect(places.last.hasCoords, isFalse);
      expect(places.last.lat, isNull);
    });

    test("the gym's own location carries its pin through", () {
      final places = allSessionPlaces(settings(), const []);
      expect(places.first.hasCoords, isTrue);
      expect(places.first.lat, closeTo(34.1808, 0.0001));
    });
  });

  group("a coach location survives being saved and read back", () {
    test("the pin round-trips", () {
      const original = TrainerLocation(
        id: "l1",
        name: "Iron Athletics",
        address: "9 Oak Ave",
        lat: 34.05,
        lng: -118.25,
      );
      // Mirrors what the service writes and reads.
      final asJson = {
        "id": original.id,
        "name": original.name,
        if (original.address != null) "address": original.address,
        if (original.lat != null) "lat": original.lat,
        if (original.lng != null) "lng": original.lng,
      };
      final back = TrainerLocation(
        id: asJson["id"]! as String,
        name: asJson["name"]! as String,
        address: asJson["address"] as String?,
        lat: (asJson["lat"] as num?)?.toDouble(),
        lng: (asJson["lng"] as num?)?.toDouble(),
      );
      expect(back.hasCoords, isTrue);
      expect(back.lat, 34.05);
      expect(back.lng, -118.25);
    });

    test("copyWith keeps the pin when only the name changes", () {
      const l = TrainerLocation(id: "l1", name: "Old", lat: 34.05, lng: -118.25);
      final renamed = l.copyWith(name: "New");
      expect(renamed.name, "New");
      expect(renamed.hasCoords, isTrue);
    });
  });

  group("how a distance reads", () {
    test("across town, one decimal", () {
      expect(formatDistance(3862), "2.4 mi");
    });

    test("close by, in feet rather than a useless 0.1 mi", () {
      // The gym across the street should not read "0.1 mi".
      expect(formatDistance(120), "400 ft");
    });

    test("very close, to the nearest foot", () {
      expect(formatDistance(20), "66 ft");
    });

    test("far away, no decimal", () {
      expect(formatDistance(40000), "25 mi");
    });

    test("the feet/miles boundary", () {
      // A quarter mile is 402m — just under reads as feet, just over as miles.
      expect(formatDistance(400).endsWith("ft"), isTrue);
      expect(formatDistance(410).endsWith("mi"), isTrue);
    });

    test("zero is not an error", () {
      expect(formatDistance(0), "0 ft");
    });
  });

  group("where a client is measured from", () {
    // Order of preference: the live device position, then the point they
    // set for themselves, then the centre of their city. The middle one
    // used to be missing entirely — the pin was used once and discarded.
    test("a saved point is recognised", () {
      const info = ClientInfo(id: "c1", name: "Tina", homeLat: 34.05, homeLng: -118.25);
      expect(info.hasHomePoint, isTrue);
    });

    test("no point means falling back to the city", () {
      const info = ClientInfo(id: "c1", name: "Tina", city: "Burbank", state: "CA");
      expect(info.hasHomePoint, isFalse);
    });

    test("half a point is not a point", () {
      // A latitude with no longitude can't be measured from; it must not
      // be treated as usable.
      const info = ClientInfo(id: "c1", name: "Tina", homeLat: 34.05);
      expect(info.hasHomePoint, isFalse);
    });

    test("the point survives an unrelated profile edit", () {
      const info = ClientInfo(id: "c1", name: "Tina", homeLat: 34.05, homeLng: -118.25);
      expect(info.copyWith(name: "Tina S").hasHomePoint, isTrue);
      expect(info.copyWith(city: "Glendale").homeLat, 34.05);
    });
  });
}

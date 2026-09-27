import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/nearest_location.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";

void main() {
  group("distance labels", () {
    LocationDistance at(double metres) => LocationDistance(
          location: const GymLocation(name: "Gym", lat: 1, lng: 1),
          metres: metres,
        );

    test("very close reads as under a tenth of a mile", () {
      expect(at(80).label, "Less than 0.1 mi away");
    });

    test("nearby keeps one decimal", () {
      // 1 mile = 1609.344 m
      expect(at(1609.344).label, "1.0 mi away");
      expect(at(3862).label, "2.4 mi away");
    });

    test("far drops the decimal — 12.37 mi is false precision", () {
      expect(at(20000).label, "12 mi away");
      expect(at(80467).label, "50 mi away");
    });

    test("miles and km conversions are right", () {
      final d = at(1609.344);
      expect(d.miles, closeTo(1.0, 0.001));
      expect(d.km, closeTo(1.609, 0.001));
    });
  });

  group("default location resolution", () {
    const main = GymLocation(name: "ONE Fitness NoHo", address: "11300 Magnolia Blvd");
    const second = GymLocation(name: "ONE Fitness Burbank", address: "Burbank");

    PlatformSettings settings({String def = "", bool extra = true}) => PlatformSettings(
          locationName: main.name,
          locationAddress: main.address,
          locations: extra ? const [second] : const [],
          defaultLocationName: def,
        );

    test("falls back to the first location when none is set", () {
      expect(settings().defaultLocation?.name, main.name);
    });

    test("honours an explicit default", () {
      expect(settings(def: second.name).defaultLocation?.name, second.name);
    });

    test("a default naming a deleted location falls back, not crashes", () {
      expect(settings(def: "Somewhere Closed Down").defaultLocation?.name, main.name);
    });

    test("no locations at all yields null rather than throwing", () {
      const empty = PlatformSettings(locationName: "", locations: []);
      expect(empty.defaultLocation, isNull);
    });
  });

  group("coach location fallback", () {
    final s = PlatformSettings(
      locationName: "ONE Fitness NoHo",
      locations: const [GymLocation(name: "ONE Fitness Burbank")],
      defaultLocationName: "ONE Fitness Burbank",
    );

    test("a coach with their own location keeps it", () {
      expect(s.locationForCoach("Coach's Studio"), "Coach's Studio");
    });

    test("a coach with none gets the gym default", () {
      expect(s.locationForCoach(null), "ONE Fitness Burbank");
    });

    test("blank counts as none", () {
      expect(s.locationForCoach("   "), "ONE Fitness Burbank");
    });
  });

  group("coordinates", () {
    test("a location is only usable for distance once geocoded", () {
      const noCoords = GymLocation(name: "A", address: "somewhere");
      const withCoords = GymLocation(name: "B", address: "somewhere", lat: 34.1, lng: -118.3);
      expect(noCoords.hasCoords, isFalse);
      expect(withCoords.hasCoords, isTrue);
    });

    test("copyWith keeps existing coordinates when none are passed", () {
      const l = GymLocation(name: "A", lat: 34.1, lng: -118.3);
      final renamed = l.copyWith(name: "B");
      expect(renamed.lat, 34.1);
      expect(renamed.lng, -118.3);
    });
  });

  test("every failure reason has a message a client can act on", () {
    for (final e in NearestError.values) {
      final msg = nearestErrorMessage(e);
      expect(msg, isNotEmpty);
      expect(msg.endsWith("."), isTrue, reason: "$e should read as a sentence");
    }
  });
}

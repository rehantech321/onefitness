import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/nearest_location.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";

void main() {
  group("which settings screen fixes which failure", () {
    test("location switched off sends you to the device settings", () {
      expect(settingsTargetFor(NearestError.serviceOff), SettingsTarget.device);
    });

    test("a denied permission sends you to the app's own settings", () {
      expect(settingsTargetFor(NearestError.denied), SettingsTarget.app);
      expect(settingsTargetFor(NearestError.deniedForever), SettingsTarget.app);
    });

    test("missing coordinates offers no settings trip — it can't help", () {
      expect(settingsTargetFor(NearestError.noCoords), isNull);
      expect(settingsTargetFor(NearestError.failed), isNull);
    });
  });

  group("distances from a point picked on the map", () {
    // Roughly North Hollywood and Burbank — about 4 miles apart.
    const noho = GymLocation(name: "NoHo", lat: 34.1706, lng: -118.3768);
    const burbank = GymLocation(name: "Burbank", lat: 34.1808, lng: -118.3090);
    const noCoords = GymLocation(name: "Unplaced", address: "somewhere");

    test("orders nearest first from the picked point", () {
      // Sitting essentially on top of NoHo.
      final d = distancesFrom(34.1706, -118.3768, [burbank, noho]);
      expect(d.first.location.name, "NoHo");
      expect(d.last.location.name, "Burbank");
    });

    test("the near one really is near and the far one really is far", () {
      final d = distancesFrom(34.1706, -118.3768, [noho, burbank]);
      expect(d.first.metres, lessThan(100));
      // ~3.9 miles; allow a wide band, this is a sanity check not a fixture.
      expect(d.last.miles, inInclusiveRange(3.0, 5.0));
    });

    test("locations with no coordinates are left out, not sorted last", () {
      final d = distancesFrom(34.1706, -118.3768, [noho, noCoords, burbank]);
      expect(d.map((x) => x.location.name), ["NoHo", "Burbank"]);
    });

    test("no placed locations yields an empty list rather than throwing", () {
      expect(distancesFrom(34.1, -118.3, const [noCoords]), isEmpty);
    });
  });
}

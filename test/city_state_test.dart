import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/booking_location.dart";
import "package:onefitness/data/models/client_info.dart";

/// City and State are geocoded together to decide which gym is nearest a
/// client. City alone is ambiguous across states, so what gets handed to
/// the geocoder matters.
void main() {
  ClientInfo who({String? city, String? state}) =>
      ClientInfo(id: "c1", name: "Test", city: city, state: state);

  group("what the geocoder is asked", () {
    test("city and state are combined", () {
      expect(clientPlaceQuery(who(city: "Burbank", state: "CA")), "Burbank, CA");
    });

    test("city alone still works — state is an improvement, not a gate", () {
      expect(clientPlaceQuery(who(city: "Burbank")), "Burbank");
    });

    test("state alone is better than nothing", () {
      expect(clientPlaceQuery(who(state: "CA")), "CA");
    });

    test("nothing set yields an empty query, not a stray comma", () {
      expect(clientPlaceQuery(who()), "");
      expect(clientPlaceQuery(who(city: "", state: "")), "");
    });

    test("whitespace-only fields are treated as unset", () {
      expect(clientPlaceQuery(who(city: "   ", state: "  ")), "");
      // A blank city must not leave a leading comma on the query.
      expect(clientPlaceQuery(who(city: "  ", state: "CA")), "CA");
    });

    test("surrounding spaces are trimmed, not passed through", () {
      expect(clientPlaceQuery(who(city: " Burbank ", state: " CA ")), "Burbank, CA");
    });
  });

  test("state survives copyWith, like every other profile field", () {
    final base = who(city: "Burbank", state: "CA");
    expect(base.copyWith(name: "Renamed").state, "CA");
    expect(base.copyWith(state: "IL").state, "IL");
  });
}

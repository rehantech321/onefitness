import "package:flutter_test/flutter_test.dart";
import "package:onefitness/core/utils/address_utils.dart";

void main() {
  group("AddressParts.parse", () {
    test("splits a full one-line address", () {
      final p = AddressParts.parse("2422 W Victory Blvd., Burbank, CA 91506");
      expect(p.street, "2422 W Victory Blvd.");
      expect(p.city, "Burbank");
      expect(p.state, "CA");
      expect(p.zip, "91506");
    });

    test("drops a trailing country", () {
      final p = AddressParts.parse("2422 W Victory Blvd, Burbank, CA 91506, USA");
      expect(p.city, "Burbank");
      expect(p.zip, "91506");
    });

    test("keeps anything it can't place in the street", () {
      final p = AddressParts.parse("Rear entrance by the car wash");
      expect(p.street, "Rear entrance by the car wash");
      expect(p.city, "");
    });

    test("a street with no city yet stays the street", () {
      final p = AddressParts.parse("2422 W Victory Blvd., CA 91506");
      expect(p.street, "2422 W Victory Blvd.");
      expect(p.city, "");
      expect(p.state, "CA");
    });

    test("compose round-trips a full address", () {
      const line = "2422 W Victory Blvd., Burbank, CA 91506";
      expect(AddressParts.parse(line).compose(), line);
    });
  });

  test("stateCode turns full US state names into codes", () {
    expect(stateCode("California"), "CA");
    expect(stateCode("ca"), "CA");
    expect(stateCode("Ontario"), "Ontario");
  });
}

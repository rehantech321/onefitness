import "package:flutter_test/flutter_test.dart";
import "package:onefitness/core/utils/notification_triggers.dart";

/// The welcome email a new client gets when their profile is created.
///
/// The copy is a const block with one `{First Name}` placeholder, so the
/// things worth pinning are that the placeholder is actually filled in, that
/// it still reads as a sentence when there's no name to use, and that the
/// sections the gym asked for are all still in there after an edit.
void main() {
  group("the greeting", () {
    test("the placeholder is replaced, with none left behind", () {
      final text = kWelcomeEmailBody.replaceAll("{First Name}", "Dana");
      expect(text, startsWith("Hi Dana,"));
      expect(text.contains("{"), isFalse, reason: "a placeholder went unfilled");
    });

    test("the placeholder appears exactly once", () {
      // More than one and a fallback greeting would read "Hi there ...
      // there" halfway down; none at all means the name never lands.
      expect("{First Name}".allMatches(kWelcomeEmailBody).length, 1);
    });
  });

  group("first name from a combined name", () {
    test("takes the first word", () {
      expect(firstNameFrom("Chris McCarthy"), "Chris");
      expect(firstNameFrom("Dana"), "Dana");
    });

    test("survives the messy ones", () {
      expect(firstNameFrom("  Marcus   Lee  "), "Marcus");
      expect(firstNameFrom(""), "");
      expect(firstNameFrom("   "), "");
    });
  });

  group("the copy itself", () {
    test("every section the gym asked for is present", () {
      for (final heading in [
        "YOUR PLAN, ALWAYS IN YOUR POCKET",
        "BOOK ON YOUR TERMS",
        "TRAINERS YOU CAN TRUST",
        "MAKE IT A GAME",
        "NEXT STEP",
      ]) {
        expect(kWelcomeEmailBody, contains(heading), reason: "$heading is gone");
      }
    });

    test("the four game features are all named", () {
      for (final feature in ["Challenges:", "Merit badges:", "Rewards:", "Squad:"]) {
        expect(kWelcomeEmailBody, contains(feature));
      }
    });

    test("it signs off with the contact address and the site", () {
      expect(kWelcomeEmailBody, contains("Info@onefitnessworkout.com"));
      expect(kWelcomeEmailBody, endsWith("ONEFitnessWorkout.com"));
    });

    test("no trailing blank lines", () {
      // Plain-text mail: whatever is in this string is exactly what lands in
      // the inbox, trailing whitespace included.
      expect(kWelcomeEmailBody.trimRight(), kWelcomeEmailBody);
    });
  });
}

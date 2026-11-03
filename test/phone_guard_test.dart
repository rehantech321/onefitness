import "package:flutter/widgets.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:onefitness/core/utils/phone_guard.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";
import "package:onefitness/data/providers/trainer_providers.dart";

void main() {
  test("matches the support number however it's formatted", () {
    const support = "8182237001";
    expect(isGymSupportNumber("818-223-7001", support), isTrue);
    expect(isGymSupportNumber("(818) 223 7001", support), isTrue);
    expect(isGymSupportNumber("+1 818 223 7001", support), isTrue);
  });

  test("a different number is allowed", () {
    expect(isGymSupportNumber("818-223-7002", "8182237001"), isFalse);
  });

  test("no support number set blocks nothing", () {
    expect(isGymSupportNumber("818-223-7001", ""), isFalse);
    expect(isGymSupportNumber("", ""), isFalse);
  });

  group("who the guard applies to", () {
    /// Runs [gymNumberError] inside a scope where the gym's line is set and
    /// [signedInAs] is whoever is editing — null for a client editing their
    /// own profile, a trainer id for a coach, "owner" for the owner.
    Future<String?> errorFor(WidgetTester tester, String? signedInAs) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(platformSettingsProvider.notifier).update(
            (s) => s.copyWith(supportPhone: "8182237001"),
          );
      if (signedInAs != null) {
        container.read(trainerAuthProvider.notifier).signIn(signedInAs);
      }
      String? result;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Builder(
            builder: (context) {
              result = gymNumberError(context, "(818) 223-7001");
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets("the owner may use the gym's number", (tester) async {
      // The gym's line is the owner's own phone. Them putting it on a
      // profile is a decision, not the slip this guard is here to catch.
      expect(await errorFor(tester, "owner"), isNull);
    });

    testWidgets("a coach may not", (tester) async {
      expect(await errorFor(tester, "t1"), kGymNumberError);
    });

    testWidgets("a client may not", (tester) async {
      expect(await errorFor(tester, null), kGymNumberError);
    });
  });
}

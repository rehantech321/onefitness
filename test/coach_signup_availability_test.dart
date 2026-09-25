import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/providers/platform_settings_provider.dart";
import "package:onefitness/features/trainer/auth/coach_signup_screen.dart";

/// Availability is what makes a coach bookable at all, so the signup form
/// must always show it and must not let an account be created without it.
void main() {
  late ProviderContainer container;

  void ignoreOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains("overflowed by")) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> boot(WidgetTester tester) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    container.read(platformSettingsProvider.notifier).update(
          (s) => s.copyWith(
            offeredSessionTypes: const ["semi-private", "one-on-one"],
            offeredDisciplines: const ["boxing"],
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: CoachSignupScreen(onBack: () {}, debugSkipCodeGate: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("availability is shown from the start, marked required",
      (tester) async {
    await boot(tester);

    // Visible before anything is picked — hiding it made it look deleted.
    expect(find.text("Availability * (required)"), findsOneWidget,
        reason: "the availability section must always be on the form");
    expect(
      find.textContaining("Choose your disciplines and session types above"),
      findsOneWidget,
      reason: "it should say what's needed first, not silently disappear",
    );
  });

  testWidgets("it explains which step is still missing", (tester) async {
    await boot(tester);

    await tester.tap(find.text("Boxing"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Choose your session types above"), findsOneWidget,
        reason: "with a discipline picked, only session types remain");

    await tester.tap(find.text("Semi-Private"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Choose your"), findsNothing,
        reason: "both prerequisites met — the editor should be usable now");
    expect(find.text("+ Semi-Private"), findsOneWidget);
  });

  testWidgets("signup is refused with no availability added", (tester) async {
    await boot(tester);
    await tester.tap(find.text("Boxing"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Semi-Private"));
    await tester.pumpAndSettle();

    // Everything else valid: first, last, title, email, phone, then the two
    // password fields last.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), "Sam");
    await tester.enterText(fields.at(1), "Coach");
    await tester.enterText(fields.at(3), "sam@example.com");
    await tester.enterText(fields.at(4), "5550100");
    final count = fields.evaluate().length;
    await tester.enterText(fields.at(count - 2), "secret123");
    await tester.enterText(fields.at(count - 1), "secret123");
    await tester.pumpAndSettle();

    final submit = find.text("Create coach profile").last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text("Add at least one availability block so clients can book you."),
      findsOneWidget,
      reason: "a coach with no availability would be invisible in booking",
    );
  });
}

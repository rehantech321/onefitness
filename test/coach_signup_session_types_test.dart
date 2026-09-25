import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/providers/platform_settings_provider.dart";
import "package:onefitness/features/trainer/auth/coach_signup_screen.dart";

/// The session types a coach can pick while creating their profile must be
/// exactly what the owner set up in Customize Platform → Services — including
/// types the owner added themselves, and excluding ones they deleted.
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

  /// Mounts the signup form past the approval-code gate.
  Future<void> boot(
    WidgetTester tester, {
    required List<String> sessionTypes,
    List<String>? disciplines,
  }) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    container.read(platformSettingsProvider.notifier).update(
          (s) => s.copyWith(
            offeredSessionTypes: sessionTypes,
            offeredDisciplines: disciplines ?? const ["boxing"],
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

  testWidgets("the owner's session types appear on the signup form",
      (tester) async {
    await boot(tester, sessionTypes: const ["semi-private", "one-on-one"]);

    expect(find.text("Session types (choose one or more)"), findsOneWidget,
        reason: "the signup form must ask for session types at all");
    expect(find.text("Semi-Private"), findsOneWidget);
    expect(find.text("One-on-One"), findsOneWidget);
  });

  testWidgets("a session type the owner added themselves appears too",
      (tester) async {
    await boot(tester,
        sessionTypes: const ["semi-private", "aerial-yoga", "small-group"]);

    // Owner-added keys have no built-in label — they read back from the key.
    expect(find.text("Aerial Yoga"), findsOneWidget);
    expect(find.text("Small Group"), findsOneWidget);
  });

  testWidgets("a session type the owner deleted is not offered",
      (tester) async {
    await boot(tester, sessionTypes: const ["semi-private"]);

    expect(find.text("Semi-Private"), findsOneWidget);
    expect(find.text("One-on-One"), findsNothing,
        reason: "a type removed in Customize Platform must not appear here");
    expect(find.text("Large Group"), findsNothing);
  });

  testWidgets("picking a type reveals its availability button", (tester) async {
    await boot(tester, sessionTypes: const ["semi-private", "one-on-one"]);

    // Availability is per session type, so nothing is offered until both a
    // discipline and a type are chosen.
    expect(find.textContaining("+ Semi-Private"), findsNothing);

    await tester.tap(find.text("Boxing"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Semi-Private"));
    await tester.pumpAndSettle();

    expect(find.text("+ Semi-Private"), findsOneWidget,
        reason: "the chosen type should be addable to availability");
    expect(find.text("+ One-on-One"), findsNothing,
        reason: "a type the coach didn't tick shouldn't be addable");
  });

  testWidgets("signing up without a session type is refused", (tester) async {
    await boot(tester, sessionTypes: const ["semi-private"]);

    await tester.tap(find.text("Boxing"));
    await tester.pumpAndSettle();
    // Everything else valid, so the only thing left to complain about is the
    // missing session type. Field order: first, last, title, email, phone …
    // with the two password fields last.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), "Sam");
    await tester.enterText(fields.at(1), "Coach");
    await tester.enterText(fields.at(3), "sam@example.com");
    await tester.enterText(fields.at(4), "5550100");
    final count = fields.evaluate().length;
    await tester.enterText(fields.at(count - 2), "secret123");
    await tester.enterText(fields.at(count - 1), "secret123");
    await tester.pumpAndSettle();

    // ".last" — the same string is also the page's own title bar.
    // Consent is validated before session types, so tick both gates or the
    // age error masks the one under test.
    final ageBox = find.text("I confirm I am 18 or older");
    await tester.ensureVisible(ageBox);
    await tester.pumpAndSettle();
    await tester.tap(ageBox);
    await tester.pumpAndSettle();
    final termsBox = find.text("I agree to the ");
    await tester.ensureVisible(termsBox);
    await tester.pumpAndSettle();
    await tester.tap(termsBox);
    await tester.pumpAndSettle();

    final submit = find.text("Create coach profile").last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text("Choose at least one session type."), findsOneWidget,
        reason: "the form should say a session type is needed");
  });

  testWidgets("no configured types: the form explains instead of blocking",
      (tester) async {
    await boot(tester, sessionTypes: const []);

    expect(find.textContaining("hasn't set up any session types"),
        findsOneWidget);
  });
}

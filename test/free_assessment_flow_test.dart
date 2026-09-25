import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/booking.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/data/providers/platform_settings_provider.dart";
import "package:onefitness/features/client/booking/booking_screen.dart";
import "package:onefitness/features/client/shell/client_shell_state.dart";

/// The free first session: a client with no membership taps "Book my free
/// session", picks Semi-Private or One-on-One, and stays in that flow.
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

    // No plan held and nothing booked — the free offer stands.
    container.read(membershipPlansProvider.notifier).setAll(const []);
    container.read(clientBookingsProvider.notifier).setAll(const []);
    container.read(platformSettingsProvider.notifier).update(
          (s) => s.copyWith(
            offeredSessionTypes: const ["semi-private", "one-on-one"],
            offeredDisciplines: const ["personal-training"],
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BookingScreen(
              onGoMemberships: () {},
              onGoSignatures: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> visibleText() => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();

  testWidgets("the free first session is offered to a client with no plan",
      (tester) async {
    await boot(tester);
    expect(find.text("Your first session is free"), findsOneWidget);
    expect(find.text("Book my free session"), findsOneWidget);
  });

  testWidgets("starting it offers Semi-Private and One-on-One",
      (tester) async {
    await boot(tester);
    await tester.tap(find.text("Book my free session"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: "starting the free session must not throw");

    expect(find.textContaining("Semi-Private"), findsWidgets,
        reason: "free session is bookable as Semi-Private; "
            "screen shows ${visibleText()}");
    expect(find.textContaining("One-on-One"), findsWidgets);
  });

  testWidgets("picking a type moves on instead of bouncing back to the start",
      (tester) async {
    await boot(tester);
    await tester.tap(find.text("Book my free session"));
    await tester.pumpAndSettle();

    final semi = find.textContaining("Semi-Private").first;
    await tester.ensureVisible(semi);
    await tester.pumpAndSettle();
    await tester.tap(semi);
    await tester.pumpAndSettle();

    // This is the regression: picking a type flipped a LocalBackScope open
    // mid-build, which threw and collapsed the screen — the client landed
    // back on the booking page with the free flow lost.
    expect(tester.takeException(), isNull,
        reason: "picking a session type must not throw");
    expect(find.text("Book my free session"), findsNothing,
        reason: "picking a type must not bounce back to the start; "
            "screen shows ${visibleText()}");
  });

  testWidgets("the free session survives leaving and returning to Booking",
      (tester) async {
    await boot(tester);
    await tester.tap(find.text("Book my free session"));
    await tester.pumpAndSettle();
    expect(container.read(freeAssessmentIntentProvider), isTrue);

    // Signing a waiver takes the client off Booking and drops them back on
    // a brand-new Booking screen. Rebuild from scratch to model that.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BookingScreen(onGoMemberships: () {}, onGoSignatures: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Booking your free physical assessment"),
        findsOneWidget,
        reason: "coming back from the waiver must resume the free session, "
            "not drop the client on the ordinary booking page; "
            "screen shows ${visibleText()}");
    expect(find.text("Book my free session"), findsNothing);
  });

  testWidgets("'Not now' leaves the free flow and restores the offer",
      (tester) async {
    await boot(tester);
    await tester.tap(find.text("Book my free session"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Not now"));
    await tester.pumpAndSettle();

    expect(container.read(freeAssessmentIntentProvider), isFalse);
    expect(find.text("Book my free session"), findsOneWidget,
        reason: "backing out should put the offer back on the page");
  });

  testWidgets("a stale intent is dropped once something has been booked",
      (tester) async {
    await boot(tester);
    await tester.tap(find.text("Book my free session"));
    await tester.pumpAndSettle();

    // They booked elsewhere in the meantime, so the offer no longer stands.
    final me = container.read(clientInfoProvider).id;
    container.read(clientBookingsProvider.notifier).setAll([
      Booking(
        id: "b1",
        clientId: me,
        trainerId: "t1",
        date: "2026-10-01",
        slot: 600,
        sessionType: "semi-private",
        discipline: "personal-training",
      ),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BookingScreen(onGoMemberships: () {}, onGoSignatures: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(freeAssessmentIntentProvider), isFalse,
        reason: "a spent offer shouldn't strand the client in the free flow");
    expect(find.textContaining("Booking your free physical assessment"),
        findsNothing);
  });
}

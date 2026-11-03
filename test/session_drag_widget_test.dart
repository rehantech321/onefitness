import "package:flutter/material.dart";
import "package:flutter/gestures.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/booking.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/trainer.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/data/providers/trainer_providers.dart";
import "package:onefitness/features/trainer/schedule/day_view.dart";

/// The Schedule day view's two drags, and the one way they could go wrong.
///
/// A session card can be picked up and dropped on a date; a client chip
/// inside that same card can be picked up and dropped on another session.
/// The chip sits inside the card, so both long-press listeners see the same
/// press — and if the card's won, a coach reaching for one client would move
/// the whole class instead. These tests pin down which one lifts.
void main() {
  // Far enough ahead that the day is never "past", whenever the suite runs —
  // a past day switches every drag off, which would make these pass for the
  // wrong reason.
  const date = "2099-06-10";
  const morning = 540; // 9:00
  const midday = 600; // 10:00

  Booking booking({
    required String id,
    required String clientId,
    required int slot,
  }) => Booking(
    id: id,
    clientId: clientId,
    trainerId: "t1",
    date: date,
    slot: slot,
    sessionType: "semi-private",
    discipline: "personal-training",
  );

  ProviderContainer seeded() {
    final container = ProviderContainer();
    container.read(trainerAuthProvider.notifier).signIn("owner");
    container.read(trainersProvider.notifier).setAll([
      const Trainer(id: "t1", name: "Alex Rivera"),
    ]);
    container.read(trainerRosterProvider.notifier).setAll([
      const ClientInfo(id: "c1", name: "Dana Whitfield"),
      const ClientInfo(id: "c2", name: "Marcus Lee"),
    ]);
    container.read(allBookingsProvider.notifier).setAll([
      booking(id: "b1", clientId: "c1", slot: morning),
      booking(id: "b2", clientId: "c2", slot: midday),
    ]);
    container.read(blockedTimesProvider.notifier).setAll([]);
    return container;
  }

  Future<List<String>> pumpDay(WidgetTester tester) async {
    final picked = <String>[];
    final container = seeded();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: DayView(
              date: date,
              onOpenClient: (_) {},
              onPickDate: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return picked;
  }

  /// Presses, holds long enough for a long-press to register, and drags —
  /// stopping with the finger still down so the feedback under it can be
  /// inspected before anything is dropped.
  Future<TestGesture> liftFrom(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    return gesture;
  }

  testWidgets("a session card lists who's in it", (tester) async {
    await pumpDay(tester);
    // First names only — the chips have to fit several to a row.
    expect(find.text("Dana"), findsOneWidget);
    expect(find.text("Marcus"), findsOneWidget);
  });

  testWidgets("holding a client chip lifts that client, not the session", (tester) async {
    await pumpDay(tester);
    final gesture = await liftFrom(tester, find.text("Dana"));

    // The feedback chip names the client in full — the session's own
    // feedback would end with how many clients are going instead. Matching
    // the "· 1 client" tail rather than the bare word, which also appears in
    // the drag hint and the owner's "2 sessions · 2 clients" summary.
    expect(find.text("Dana Whitfield"), findsOneWidget);
    expect(find.textContaining("· 1 client"), findsNothing);

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets("holding the card body lifts the whole session", (tester) async {
    await pumpDay(tester);
    // The time line belongs to the card, not to any chip.
    final gesture = await liftFrom(tester, find.textContaining("9:00 AM").first);

    expect(find.textContaining("1 client"), findsOneWidget);
    expect(find.text("Dana Whitfield"), findsNothing);

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets("the date strip moves the view when a date is tapped", (tester) async {
    final picked = await pumpDay(tester);
    // The strip starts three days before the day on screen, so the 11th is
    // the cell four along.
    await tester.tap(find.text("11").first);
    await tester.pump();
    expect(picked, ["2099-06-11"]);
  });

  testWidgets("a past day offers no drag at all", (tester) async {
    // Nothing on a day that has been and gone should lift: there is no
    // moving a session that already happened.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(trainerAuthProvider.notifier).signIn("owner");
    container.read(trainersProvider.notifier).setAll([
      const Trainer(id: "t1", name: "Alex Rivera"),
    ]);
    container.read(trainerRosterProvider.notifier).setAll([
      const ClientInfo(id: "c1", name: "Dana Whitfield"),
    ]);
    container.read(allBookingsProvider.notifier).setAll([
      Booking(
        id: "b1",
        clientId: "c1",
        trainerId: "t1",
        date: "2000-01-10",
        slot: morning,
        sessionType: "semi-private",
        discipline: "personal-training",
      ),
    ]);
    container.read(blockedTimesProvider.notifier).setAll([]);
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: DayView(date: "2000-01-10", onOpenClient: (_) {}, onPickDate: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Dana"), findsOneWidget);
    final gesture = await liftFrom(tester, find.text("Dana"));
    expect(find.text("Dana Whitfield"), findsNothing);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });
}

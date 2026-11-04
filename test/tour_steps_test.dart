import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/widgets/coachmark_overlay.dart";
import "package:onefitness/data/models/tour_step.dart";

/// The walkthrough overlays, and the one way they go wrong.
///
/// Every step points at a widget by GlobalKey. When that widget isn't on
/// screen there is no hole in the scrim and no tooltip either — a tap-to-
/// advance black screen that still counts towards the total, so the numbers
/// jump. Reported as "2 and 3 are missing": Workout Plan and Nutrition Plan
/// had left the drawer for the Plans tab, and their steps stayed behind.
void main() {
  /// Renders [steps] over a column holding a target for each of [present].
  Future<void> pumpTour(
    WidgetTester tester, {
    required List<TourStep> steps,
    required Map<String, GlobalKey> keys,
    required Set<String> present,
    VoidCallback? onDone,
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  for (final k in present)
                    SizedBox(key: keys[k], height: 40, width: 200, child: Text(k)),
                ],
              ),
              CoachmarkOverlay(
                steps: steps,
                keys: keys,
                onDone: onDone ?? () {},
              ),
            ],
          ),
        ),
      ),
    );
    // One frame to build the targets, another for the overlay's measure.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  group("the drawer tour", () {
    test("names each step once", () {
      final keys = kDrawerTourSteps.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length, reason: "a duplicated step");
    });

    test("every step has a GlobalKey to spotlight", () {
      // The key map is built from the step list, so this is really a check
      // that nothing looks up a key by a name it typed out by hand.
      for (final s in kDrawerTourSteps) {
        expect(kDrawerTourKeys[s.key], isNotNull, reason: "${s.key} has no key");
      }
    });

    test("the two steps that pointed at nothing are gone", () {
      // Workout Plan and Nutrition Plan live in the Plans bottom tab, not in
      // the drawer. If either is ever put back in the menu, its step can
      // come back with it.
      final keys = kDrawerTourSteps.map((s) => s.key);
      expect(keys, isNot(contains("drawer-plans")));
      expect(keys, isNot(contains("drawer-nutrition")));
    });

    testWidgets("counts off without a gap, start to finish", (tester) async {
      var done = false;
      await pumpTour(
        tester,
        steps: kDrawerTourSteps,
        keys: kDrawerTourKeys,
        present: kDrawerTourSteps.map((s) => s.key).toSet(),
        onDone: () => done = true,
      );

      final total = kDrawerTourSteps.length;
      for (var n = 1; n <= total; n++) {
        expect(find.text("$n of $total"), findsOneWidget, reason: "step $n");
        // The step's own title is on screen, so no step is a blank bubble.
        expect(find.text(kDrawerTourSteps[n - 1].title), findsOneWidget);
        await tester.tap(find.text(n == total ? "Got it" : "Next"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(done, isTrue, reason: "the tour never finished");
    });
  });

  group("a step with nothing to point at", () {
    testWidgets("is left out, and the total says so", (tester) async {
      final keys = {for (final k in ["a", "gone", "b"]) k: GlobalKey()};
      await pumpTour(
        tester,
        steps: const [
          TourStep("a", "First", "..."),
          TourStep("gone", "Removed", "..."),
          TourStep("b", "Second", "..."),
        ],
        keys: keys,
        present: {"a", "b"},
      );

      expect(find.text("1 of 2"), findsOneWidget);
      expect(find.text("First"), findsOneWidget);

      await tester.tap(find.text("Next"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      // Straight to the next real step — no black frame in between.
      expect(find.text("2 of 2"), findsOneWidget);
      expect(find.text("Second"), findsOneWidget);
      expect(find.text("Removed"), findsNothing);
    });

    testWidgets("a tour with no targets at all ends itself", (tester) async {
      // Otherwise an invisible overlay sits over the screen swallowing taps
      // for the rest of the session.
      var done = false;
      await pumpTour(
        tester,
        steps: const [TourStep("gone", "Removed", "...")],
        keys: {"gone": GlobalKey()},
        present: const {},
        onDone: () => done = true,
      );
      expect(done, isTrue);
    });
  });

  group("the dashboard tour", () {
    test("every step has a GlobalKey to spotlight", () {
      for (final s in kDashboardTourSteps) {
        expect(kDashboardTourKeys[s.key], isNotNull, reason: "${s.key} has no key");
      }
    });

    test("names each step once", () {
      final keys = kDashboardTourSteps.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}

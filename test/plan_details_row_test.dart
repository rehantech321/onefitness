import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/membership_plan.dart";
import "package:onefitness/features/client/drawer_screens/membership_hub_screen.dart";

/// The Plan Details card on the Access Hub.
///
/// Two faults showed up in the same row. The "Covers" value ran off the
/// screen edge and sat flush against its own label — and what it said was
/// wrong anyway, because every session type that wasn't semi-private was
/// labelled "One-on-One".
void main() {
  MembershipPlan plan(List<String> allowedTypes) => MembershipPlan(
        id: "p",
        name: "10 Semi-Private Membership",
        kind: PlanKind.membership,
        allowedTypes: allowedTypes,
      );

  group("what a plan covers", () {
    test("names each session type properly", () {
      // The bug: these four rendered as "Semi-Private, One-on-One,
      // One-on-One, One-on-One".
      expect(
        coversLabel(plan(["semi-private", "one-on-one", "large-group", "assessment-call"])),
        "Semi-Private, One-on-One, Large Group, Intake Call",
      );
    });

    test("a single type reads on its own", () {
      expect(coversLabel(plan(["semi-private"])), "Semi-Private");
      expect(coversLabel(plan(["one-on-one"])), "One-on-One");
    });

    test("a service the owner added gets its own name", () {
      // Not absorbed into "One-on-One" just for being unrecognised.
      final label = coversLabel(plan(["boxing-clinic"]));
      expect(label, isNot("One-on-One"));
      expect(label.toLowerCase(), contains("boxing"));
    });

    test("the same type twice is listed once", () {
      expect(coversLabel(plan(["one-on-one", "one-on-one"])), "One-on-One");
    });

    test("covering nothing produces nothing", () {
      expect(coversLabel(plan(const [])), "");
    });

    test("order follows the plan, not the label mapping", () {
      expect(
        coversLabel(plan(["one-on-one", "semi-private"])),
        "One-on-One, Semi-Private",
      );
    });
  });

  group("the detail row", () {
    Future<void> pump(WidgetTester tester, String label, String value, {double width = 360}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: PlanDetailRow(label: label, value: value),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets("a long value wraps instead of running off the edge", (tester) async {
      // A bare Text in a spaceBetween Row had no width to wrap into, so this
      // overflowed the screen. An overflow raises a FlutterError, which the
      // test harness surfaces as a failure.
      await pump(tester, "Type", "Membership");
      final oneLine = tester.getSize(find.byType(PlanDetailRow)).height;

      await pump(tester, "Covers", "Semi-Private, One-on-One, Large Group, Intake Call, Intake In-Person");
      expect(tester.takeException(), isNull);
      expect(find.text("Covers"), findsOneWidget);

      // Measured against a real one-line row rather than a guessed pixel
      // count: proves it genuinely wrapped rather than being clipped.
      final wrapped = tester.getSize(find.byType(PlanDetailRow)).height;
      expect(wrapped, greaterThan(oneLine * 1.5));
    });

    testWidgets("label and value never touch", (tester) async {
      // "CoversSemi-Private" — spaceBetween's gap is whatever space is left,
      // which is nothing once the children fill the line.
      await pump(tester, "Covers", "Semi-Private, One-on-One, Large Group, Intake Call");
      final labelRight = tester.getTopRight(find.text("Covers")).dx;
      final valueLeft = tester.getTopLeft(find.byType(Text).last).dx;
      expect(valueLeft - labelRight, greaterThanOrEqualTo(16.0));
    });

    testWidgets("a short value still sits right-aligned on one line", (tester) async {
      await pump(tester, "Type", "Membership");
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.text("Membership")).height,
        lessThan(24),
        reason: "a short value shouldn't wrap to a second line",
      );
      // Hard against the right edge, as before the fix.
      final rowRight = tester.getBottomRight(find.byType(PlanDetailRow)).dx;
      final valueRight = tester.getBottomRight(find.text("Membership")).dx;
      expect(rowRight - valueRight, lessThan(1.0));
    });

    testWidgets("holds up on a narrow phone", (tester) async {
      await pump(tester, "Covers", "Semi-Private, One-on-One, Large Group", width: 240);
      expect(tester.takeException(), isNull);
    });
  });
}

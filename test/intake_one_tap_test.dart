import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/features/client/intake/intake_area_screen.dart";

/// Opening an intake form in one tap.
///
/// Tapping "Personalized Training Intake" on a client's Profile used to land
/// on the list of forms — the same three rows again — so reaching the form
/// took two taps. The Profile row now names the form it wants, and the
/// intake screen opens straight into it, ready to fill in.
void main() {
  ClientRecord client({bool trainingDone = false}) => ClientRecord(
    id: "c1",
    intake: {
      if (trainingDone)
        "personalTraining": const IntakeRecord(
          answers: {"goal": "Lose fat"},
          completed: true,
          at: "2026-05-14",
          by: "Client",
        ),
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    required ClientRecord record,
    String? initialOpenKey,
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IntakeAreaScreen(
              profileId: "p1",
              client: record,
              who: "trainer",
              initialOpenKey: initialOpenKey,
              onSaved: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The editor's own subtitle — present only when a form is open to fill in.
  final editorOpen = find.textContaining("Fill what you can");

  /// The first question of the real Training Intake schema.
  final firstQuestion = find.text("How did you hear about ONE Fitness?");

  testWidgets("with no form named, it opens on the list", (tester) async {
    // The Intake tab reached from the tab bar behaves as it always has.
    await pump(tester, record: client());
    expect(editorOpen, findsNothing);
    expect(firstQuestion, findsNothing);
  });

  testWidgets("naming a form opens that form, not the list", (tester) async {
    await pump(tester, record: client(), initialOpenKey: "personalTraining");
    expect(editorOpen, findsOneWidget);
    expect(firstQuestion, findsOneWidget);
  });

  testWidgets("a completed form opens ready to edit, not read-only", (tester) async {
    // Tapping a named form is asking to work on it. Landing on the read-only
    // view would mean a third tap to reach the same place.
    await pump(
      tester,
      record: client(trainingDone: true),
      initialOpenKey: "personalTraining",
    );
    expect(editorOpen, findsOneWidget);
    // The read-only view's own controls are the tell.
    expect(find.text("Edit answers"), findsNothing);
    expect(find.text("Add another"), findsNothing);
  });

  testWidgets("an unknown key falls back to the list rather than a blank screen", (tester) async {
    await pump(tester, record: client(), initialOpenKey: "nope");
    expect(editorOpen, findsNothing);
  });

  testWidgets("the nutrition row opens the nutrition form", (tester) async {
    // Each row must open its own form, not whichever one happens to be first.
    await pump(tester, record: client(), initialOpenKey: "nutritional");
    expect(editorOpen, findsOneWidget);
    expect(firstQuestion, findsNothing);
  });
}

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/features/client/intake/intake_answers_screen.dart";

/// Coaches and admin reading a client's completed intake.
///
/// Two things are being pinned down here. First, that the read-only view and
/// the editable form agree on which questions exist — they share
/// [intakeQuestionVisible] precisely so a coach can never read back a
/// question the client was never shown. Second, that every answer shape the
/// form can produce renders as something a coach can actually read, including
/// the ones it can't: a skipped question has to say so rather than vanish.
void main() {
  const q = IntakeQuestion(id: "goal", label: "Main goal", type: "single", options: ["Lose fat", "Build muscle"]);

  group("intakeQuestionVisible", () {
    test("a question without showIf is always visible", () {
      expect(intakeQuestionVisible(q, const {}), isTrue);
      expect(intakeQuestionVisible(q, const {"anything": "else"}), isTrue);
    });

    const gated = IntakeQuestion(
      id: "injuryDetail",
      label: "Tell us about the injury",
      type: "textarea",
      showIfId: "injured",
      showIfValue: "Yes",
    );

    test("shows once its controlling answer matches", () {
      expect(intakeQuestionVisible(gated, const {"injured": "Yes"}), isTrue);
    });

    test("stays hidden on a different answer", () {
      expect(intakeQuestionVisible(gated, const {"injured": "No"}), isFalse);
    });

    test("stays hidden when the controlling question was never answered", () {
      expect(intakeQuestionVisible(gated, const {}), isFalse);
    });

    test("a multi-select controller matches on any picked option", () {
      expect(
        intakeQuestionVisible(gated, const {
          "injured": ["Yes", "Previously"],
        }),
        isTrue,
      );
      expect(
        intakeQuestionVisible(gated, const {
          "injured": ["No"],
        }),
        isFalse,
      );
      expect(intakeQuestionVisible(gated, const {"injured": <String>[]}), isFalse);
    });
  });

  group("IntakeAnswersScreen", () {
    const schema = IntakeSchema(
      title: "Personalized Training Intake",
      sections: [
        IntakeSection(
          title: "Background",
          questions: [
            q,
            IntakeQuestion(id: "equipment", label: "Equipment", type: "multi", options: ["Barbell", "Bands"]),
            IntakeQuestion(id: "effort", label: "Usual effort", type: "scale", min: 1, max: 10),
            IntakeQuestion(id: "notes", label: "Anything else", type: "textarea"),
            IntakeQuestion(
              id: "injuryDetail",
              label: "Tell us about the injury",
              type: "textarea",
              showIfId: "goal",
              showIfValue: "Build muscle",
            ),
          ],
        ),
      ],
    );

    Future<void> pump(WidgetTester tester, IntakeRecord record, {VoidCallback? onEdit}) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntakeAnswersScreen(
              schema: schema,
              record: record,
              profileId: "client-1",
              assessmentKey: "nutritional",
              onBack: () {},
              onEdit: onEdit ?? () {},
            ),
          ),
        ),
      );
    }

    testWidgets("shows who completed it and when", (tester) async {
      await pump(tester, const IntakeRecord(answers: {}, completed: true, at: "2026-10-02", by: "Client"));
      expect(find.text("Completed by Client · 2026-10-02"), findsOneWidget);
    });

    testWidgets("renders each answer shape readably", (tester) async {
      await pump(
        tester,
        const IntakeRecord(
          answers: {
            "goal": "Lose fat",
            "equipment": ["Barbell", "Bands"],
            "effort": 7,
            "notes": "Shift work, trains late.",
          },
          completed: true,
          at: "2026-10-02",
          by: "Client",
        ),
      );
      expect(find.text("Lose fat"), findsOneWidget);
      expect(find.text("Barbell, Bands"), findsOneWidget);
      // A bare "7" would leave a coach guessing the scale.
      expect(find.text("7 / 10"), findsOneWidget);
      expect(find.text("Shift work, trains late."), findsOneWidget);
    });

    testWidgets("says so when a question was skipped, rather than dropping it", (tester) async {
      await pump(tester, const IntakeRecord(answers: {"goal": "Lose fat"}, completed: true, by: "Client"));
      expect(find.text("Anything else"), findsOneWidget);
      // goal, equipment, effort, notes — all but the gated one.
      expect(find.text("Not answered"), findsNWidgets(3));
    });

    testWidgets("empty answers count as unanswered", (tester) async {
      await pump(
        tester,
        const IntakeRecord(
          answers: {"goal": "   ", "equipment": <String>[], "notes": ""},
          completed: true,
          by: "Client",
        ),
      );
      expect(find.text("Not answered"), findsNWidgets(4));
    });

    testWidgets("hides a question the client was never shown", (tester) async {
      await pump(tester, const IntakeRecord(answers: {"goal": "Lose fat"}, completed: true, by: "Client"));
      expect(find.text("Tell us about the injury"), findsNothing);

      await pump(tester, const IntakeRecord(answers: {"goal": "Build muscle"}, completed: true, by: "Client"));
      expect(find.text("Tell us about the injury"), findsOneWidget);
    });

    testWidgets("warns that editing overwrites who filled it in", (tester) async {
      await pump(tester, const IntakeRecord(answers: {}, completed: true, by: "Client"));
      expect(
        find.textContaining("re-files the form under your name"),
        findsOneWidget,
      );
    });

    testWidgets("editing is a deliberate tap, not the default", (tester) async {
      var edited = false;
      await pump(
        tester,
        const IntakeRecord(answers: {"goal": "Lose fat"}, completed: true, by: "Client"),
        onEdit: () => edited = true,
      );
      // Nothing on this screen can save over the record.
      expect(find.text("Save & mark complete"), findsNothing);
      await tester.tap(find.text("Edit answers"));
      expect(edited, isTrue);
    });
  });
}

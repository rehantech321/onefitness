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

    Future<void> pump(
      WidgetTester tester,
      IntakeRecord record, {
      VoidCallback? onEdit,
      VoidCallback? onFillAgain,
    }) async {
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
              onFillAgain: onFillAgain,
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

    // Filling a form again used to overwrite the answers outright. The
    // earlier picture of a client — the goal they started with, the injury
    // they didn't have yet — is the part a coach actually wants before a
    // session, so a re-intake now keeps it.
    group("earlier submissions", () {
      const withHistory = IntakeRecord(
        answers: {"goal": "Build muscle"},
        completed: true,
        at: "2026-11-02",
        by: "Client",
        history: [
          IntakeSubmission(
            answers: {"goal": "Lose fat"},
            at: "2026-05-14",
            by: "Client",
          ),
        ],
      );

      // SectionLabel renders its text uppercased.
      testWidgets("a form filled once shows no picker", (tester) async {
        await pump(tester, const IntakeRecord(answers: {}, completed: true, at: "2026-10-02"));
        expect(find.text("SUBMISSIONS"), findsNothing);
      });

      testWidgets("lists the current submission and the ones it replaced", (tester) async {
        await pump(tester, withHistory);
        expect(find.text("SUBMISSIONS"), findsOneWidget);
        expect(find.text("2026-11-02"), findsOneWidget);
        expect(find.text("2026-05-14"), findsOneWidget);
        expect(find.text("Current"), findsOneWidget);
        expect(find.text("Replaced"), findsOneWidget);
      });

      testWidgets("opens on the current answers", (tester) async {
        await pump(tester, withHistory);
        expect(find.text("Build muscle"), findsOneWidget);
        expect(find.text("Lose fat"), findsNothing);
      });

      testWidgets("picking an earlier one shows what was said then", (tester) async {
        await pump(tester, withHistory);
        await tester.tap(find.text("2026-05-14"));
        await tester.pump();

        expect(find.text("Lose fat"), findsOneWidget);
        expect(find.text("Build muscle"), findsNothing);
      });

      testWidgets("an earlier submission can't be edited", (tester) async {
        // Editing writes to the live record, so offering it while reading a
        // superseded one would imply history can be rewritten.
        await pump(tester, withHistory);
        expect(find.text("Edit answers"), findsOneWidget);

        await tester.tap(find.text("2026-05-14"));
        await tester.pump();

        expect(find.text("Edit answers"), findsNothing);
        expect(find.text("Back to current"), findsOneWidget);
      });

      testWidgets("and gets you back to the current ones", (tester) async {
        await pump(tester, withHistory);
        await tester.tap(find.text("2026-05-14"));
        await tester.pump();
        await tester.tap(find.text("Back to current"));
        await tester.pump();

        expect(find.text("Build muscle"), findsOneWidget);
        expect(find.text("Edit answers"), findsOneWidget);
      });

      testWidgets("a question answered then but not now still reads back", (tester) async {
        // The two submissions are rendered against the same schema, so an
        // answer that has since been cleared must still show on the old one.
        await pump(
          tester,
          const IntakeRecord(
            answers: {"goal": "Build muscle"},
            completed: true,
            at: "2026-11-02",
            history: [
              IntakeSubmission(
                answers: {"goal": "Build muscle", "notes": "bad shoulder"},
                at: "2026-05-14",
              ),
            ],
          ),
        );
        expect(find.text("bad shoulder"), findsNothing);

        await tester.tap(find.text("2026-05-14"));
        await tester.pump();
        expect(find.text("bad shoulder"), findsOneWidget);
      });
    });
  });

  group("correcting versus re-filling", () {
    // These are different acts and must not share a button. A coach fixing a
    // mistyped weight is still the same submission; a client answering the
    // questionnaire again six months on is a new one. Collapsing them would
    // either bury real re-intakes under typo fixes or lose the earlier
    // answers entirely.
    const schema = IntakeSchema(
      title: "Nutrition Program Intake",
      sections: [
        IntakeSection(
          title: "Background",
          questions: [IntakeQuestion(id: "goal", label: "Main goal", type: "text")],
        ),
      ],
    );
    const record = IntakeRecord(answers: {"goal": "Lose fat"}, completed: true, at: "2026-05-14");

    Future<void> pump(WidgetTester tester, {VoidCallback? onFillAgain}) async {
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
              onEdit: () {},
              onFillAgain: onFillAgain,
            ),
          ),
        ),
      );
    }

    testWidgets("a coach gets both actions", (tester) async {
      await pump(tester, onFillAgain: () {});
      expect(find.text("Edit answers"), findsOneWidget);
      expect(find.text("Add another"), findsOneWidget);
    });

    testWidgets("a client gets only the correction", (tester) async {
      // Re-filling is the coach's call; a client reopening their own intake
      // is nearly always fixing what they just typed.
      await pump(tester);
      expect(find.text("Edit answers"), findsOneWidget);
      expect(find.text("Add another"), findsNothing);
    });

    testWidgets("the hint explains the difference when both are offered", (tester) async {
      await pump(tester, onFillAgain: () {});
      expect(find.textContaining("Add another starts a blank copy"), findsOneWidget);
    });

    testWidgets("and doesn't mention re-filling when it isn't on offer", (tester) async {
      await pump(tester);
      expect(find.textContaining("Add another"), findsNothing);
      expect(find.textContaining("replacing the record"), findsOneWidget);
    });

    testWidgets("Add another is what fires the fresh-submission path", (tester) async {
      var fillAgain = false;
      await pump(tester, onFillAgain: () => fillAgain = true);
      await tester.tap(find.text("Add another"));
      expect(fillAgain, isTrue);
    });
  });

  group("superseding a submission", () {
    const first = IntakeRecord(
      answers: {"goal": "Lose fat"},
      completed: true,
      at: "2026-05-14",
      by: "Client",
    );
    const second = IntakeRecord(
      answers: {"goal": "Build muscle"},
      completed: true,
      at: "2026-11-02",
      by: "Trainer/Coach",
    );

    test("keeps the replaced answers, newest first", () {
      final merged = first.supersededBy(second);
      expect(merged.answers, {"goal": "Build muscle"});
      expect(merged.at, "2026-11-02");
      expect(merged.history, hasLength(1));
      expect(merged.history.first.answers, {"goal": "Lose fat"});
      expect(merged.history.first.at, "2026-05-14");
      expect(merged.history.first.by, "Client");
    });

    test("stacks each later submission on the front", () {
      const third = IntakeRecord(answers: {"goal": "Strength"}, completed: true, at: "2027-01-08");
      final merged = first.supersededBy(second).supersededBy(third);
      expect(merged.answers, {"goal": "Strength"});
      expect(
        merged.history.map((h) => h.at).toList(),
        ["2026-11-02", "2026-05-14"],
      );
    });

    test("a form that was never completed isn't archived", () {
      // Otherwise opening a blank form and saving would stack up empty
      // entries that say nothing about the client.
      const blank = IntakeRecord();
      final merged = blank.supersededBy(second);
      expect(merged.history, isEmpty);
      expect(merged.answers, {"goal": "Build muscle"});
    });

    test("history already on the record survives an incomplete predecessor", () {
      const blankWithPast = IntakeRecord(
        history: [IntakeSubmission(answers: {"goal": "Lose fat"}, at: "2026-05-14")],
      );
      expect(blankWithPast.supersededBy(second).history, hasLength(1));
    });

    test("stops at the cap rather than growing without limit", () {
      // An intake entry rides along in every roster load, so this can't grow
      // forever.
      var rec = first;
      for (var i = 0; i < kMaxIntakeHistory + 5; i++) {
        rec = rec.supersededBy(IntakeRecord(answers: const {}, completed: true, at: "fill-$i"));
      }
      expect(rec.history, hasLength(kMaxIntakeHistory));
      // The most recent ones are the ones kept.
      expect(rec.history.first.at, "fill-${kMaxIntakeHistory + 3}");
    });
  });

  group("IntakeSubmission round-trips", () {
    test("survives a trip through JSON", () {
      const s = IntakeSubmission(
        answers: {"goal": "Lose fat", "equipment": ["Barbell"]},
        at: "2026-05-14",
        by: "Client",
      );
      final back = IntakeSubmission.fromJson(s.toJson());
      expect(back.answers, s.answers);
      expect(back.at, s.at);
      expect(back.by, s.by);
    });

    test("reads a record written before history existed", () {
      // Every intake already on file predates this, and the web app still
      // writes entries without it.
      final back = IntakeSubmission.fromJson(const {"answers": {"goal": "Lose fat"}});
      expect(back.answers, {"goal": "Lose fat"});
      expect(back.at, isNull);
      expect(back.attachments, isEmpty);
    });

    test("tolerates a malformed answers field", () {
      final back = IntakeSubmission.fromJson(const {"answers": "not a map"});
      expect(back.answers, isEmpty);
    });
  });
}

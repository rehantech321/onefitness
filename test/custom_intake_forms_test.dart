import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/intake_forms.dart";
import "package:onefitness/data/models/intake_form_template.dart";
import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/features/client/intake/intake_answers_screen.dart";
import "package:onefitness/features/trainer/memberships/manage_intake_forms_screen.dart";

/// Gym-defined intake forms.
///
/// The whole design turns on one rule: what a client was asked, and what they
/// answered, must stay readable forever. A form is never edited in place and
/// never deleted — revising it writes a new version, retiring it archives it
/// — and a submission is always read back against the version it was given
/// against. These tests pin that rule at each layer it has to hold.
void main() {
  IntakeFormTemplate template({
    String key = "supplements",
    int version = 1,
    String title = "Supplement Questionnaire",
    bool archived = false,
    List<IntakeSection>? sections,
  }) =>
      IntakeFormTemplate(
        key: key,
        version: version,
        title: title,
        archived: archived,
        sections: sections ??
            const [
              IntakeSection(
                title: "Current stack",
                questions: [
                  IntakeQuestion(id: "daily", label: "What do you take daily?", type: "text"),
                ],
              ),
            ],
      );

  group("a form survives the round trip to the database", () {
    test("keeps its questions, options and scale", () {
      final t = template(
        sections: const [
          IntakeSection(
            title: "Stack",
            questions: [
              IntakeQuestion(id: "daily", label: "Taken daily?", type: "text"),
              IntakeQuestion(
                id: "stims",
                label: "Any stimulants?",
                type: "single",
                options: ["Yes", "No"],
              ),
              IntakeQuestion(id: "effort", label: "Effort", type: "scale", min: 1, max: 10),
            ],
          ),
        ],
      );

      final back = IntakeFormTemplate.fromJson(t.toJson());
      expect(back.key, t.key);
      expect(back.version, t.version);
      expect(back.title, t.title);
      expect(back.sections.single.questions, hasLength(3));
      expect(back.sections.single.questions[1].options, ["Yes", "No"]);
      expect(back.sections.single.questions[2].max, 10);
    });

    test("an unknown question type degrades to text rather than vanishing", () {
      // A type neither renderer knows would draw as nothing at all — a
      // question the client never sees and the coach never knows was asked.
      final q = IntakeQuestion.fromJson(const {
        "id": "x",
        "label": "Something",
        "type": "carousel",
      });
      expect(q.type, "text");
      expect(q.label, "Something");
    });

    test("a row with no schema reads as a form with no sections", () {
      final back = IntakeFormTemplate.fromJson(const {"key": "k", "title": "T"});
      expect(back.sections, isEmpty);
      expect(back.version, 1);
    });
  });

  group("the catalogue", () {
    test("built-in forms are listed on their own when the gym has none", () {
      expect(intakeFormsWith(const []), same(kIntakeForms));
    });

    test("gym forms are added as their own group", () {
      final groups = intakeFormsWith([template()]);
      expect(groups.length, kIntakeForms.length + 1);
      expect(groups.last.assessments.single.title, "Supplement Questionnaire");
    });

    test("a gym form looks like any other assessment", () {
      // Every screen that draws an assessment must not care where it came
      // from, or custom forms would need parallel rendering everywhere.
      final a = template().asAssessment;
      expect(a.key, "supplements");
      expect(a.schema, isNotNull);
      expect(a.schema!.sections.single.questions.single.label, "What do you take daily?");
    });

    test("built-in keys still resolve", () {
      expect(assessmentDefFor("personalTraining")?.title, "Personalized Training Intake");
    });

    test("a gym key resolves through the custom list", () {
      expect(
        assessmentDefFor("supplements", custom: [template()])?.title,
        "Supplement Questionnaire",
      );
    });

    test("a retired form still resolves, so its answers can be read", () {
      // The one thing archiving must not do is make past answers unreadable.
      final def = assessmentDefFor("supplements", custom: [template(archived: true)]);
      expect(def, isNotNull);
      expect(def!.schema!.sections, isNotEmpty);
    });

    test("an unknown key resolves to nothing", () {
      expect(assessmentDefFor("nope", custom: [template()]), isNull);
    });
  });

  group("picking the right version", () {
    final v1 = template(version: 1, title: "Supplements v1");
    final v2 = template(version: 2, title: "Supplements v2");
    final other = template(key: "mobility", version: 7, title: "Mobility");
    final all = [v1, v2, other];

    test("the newest version is the one offered", () {
      expect(newestTemplateFor("supplements", all)?.version, 2);
    });

    test("versions of other forms don't interfere", () {
      expect(newestTemplateFor("mobility", all)?.title, "Mobility");
    });

    test("a submission reads against the version it was filled against", () {
      expect(templateVersionFor("supplements", 1, all)?.title, "Supplements v1");
      expect(templateVersionFor("supplements", 2, all)?.title, "Supplements v2");
    });

    test("a submission with no recorded version falls back to the newest", () {
      // Answers predating versioning. Showing them against today's questions
      // is imperfect; showing nothing would lose them entirely.
      expect(templateVersionFor("supplements", null, all)?.version, 2);
    });

    test("a version that isn't there falls back rather than disappearing", () {
      expect(templateVersionFor("supplements", 99, all)?.version, 2);
    });
  });

  group("question ids", () {
    // Ids key the stored answers. If the same label ever produced a different
    // id, new answers would be filed where the old ones aren't.
    test("a label becomes a usable identifier", () {
      expect(slugify("What do you take daily?"), "what_do_you_take_daily");
    });

    test("punctuation and spacing collapse", () {
      expect(slugify("  Height / weight —  goal!  "), "height_weight_goal");
    });

    test("an identifier always opens with a letter", () {
      // Migration 37's key_shape check requires it, and "5k time" would
      // otherwise start with a digit.
      expect(slugify("5k time"), "q5k_time");
      expect(RegExp(r"^[a-z][a-zA-Z0-9_]*$").hasMatch(slugify("5k time")), isTrue);
      // A label with nothing alphanumeric in it still has to yield a legal id.
      expect(RegExp(r"^[a-z][a-zA-Z0-9_]*$").hasMatch(slugify("???")), isTrue);
    });

    test("a long label is cut to something storable", () {
      expect(slugify("a" * 200).length, lessThanOrEqualTo(40));
    });

    test("duplicates are numbered rather than colliding", () {
      final used = <String>{"goal"};
      expect(uniqueId("goal", used), "goal_2");
      used.add("goal_2");
      expect(uniqueId("goal", used), "goal_3");
    });

    test("a free identifier is left alone", () {
      expect(uniqueId("goal", const {}), "goal");
    });
  });

  group("reading an answer given to an older version", () {
    // The payoff for all of the above: revising a form must not change what
    // an earlier client appears to have been asked.
    const v1 = IntakeSchema(
      title: "Supplements",
      sections: [
        IntakeSection(
          title: "Stack",
          questions: [IntakeQuestion(id: "daily", label: "What do you take daily?", type: "text")],
        ),
      ],
    );
    const v2 = IntakeSchema(
      title: "Supplements",
      sections: [
        IntakeSection(
          title: "Stack",
          questions: [
            IntakeQuestion(id: "daily", label: "List every supplement, with doses", type: "text"),
          ],
        ),
      ],
    );

    Future<void> pump(WidgetTester tester, IntakeRecord record) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntakeAnswersScreen(
              schema: v2,
              schemaFor: (version) => version == 1 ? v1 : v2,
              record: record,
              profileId: "client-1",
              assessmentKey: "supplements",
              onBack: () {},
              onEdit: () {},
            ),
          ),
        ),
      );
    }

    testWidgets("the current answer uses the current wording", (tester) async {
      await pump(
        tester,
        const IntakeRecord(
          answers: {"daily": "creatine"},
          completed: true,
          at: "2026-11-02",
          templateVersion: 2,
        ),
      );
      expect(find.text("List every supplement, with doses"), findsOneWidget);
      expect(find.text("What do you take daily?"), findsNothing);
    });

    testWidgets("an older submission keeps the question it was asked", (tester) async {
      await pump(
        tester,
        const IntakeRecord(
          answers: {"daily": "creatine"},
          completed: true,
          at: "2026-11-02",
          templateVersion: 2,
          history: [
            IntakeSubmission(
              answers: {"daily": "whey"},
              at: "2026-05-14",
              templateVersion: 1,
            ),
          ],
        ),
      );

      await tester.tap(find.text("2026-05-14"));
      await tester.pump();

      expect(find.text("What do you take daily?"), findsOneWidget);
      expect(find.text("whey"), findsOneWidget);
      expect(find.text("List every supplement, with doses"), findsNothing);
    });
  });

  group("the version travels with the answers", () {
    test("archiving a submission carries its version along", () {
      // Without this an archived submission would be read back against
      // whatever the form says today.
      const first = IntakeRecord(
        answers: {"daily": "whey"},
        completed: true,
        at: "2026-05-14",
        templateVersion: 1,
      );
      const second = IntakeRecord(
        answers: {"daily": "creatine"},
        completed: true,
        at: "2026-11-02",
        templateVersion: 2,
      );

      final merged = first.supersededBy(second);
      expect(merged.templateVersion, 2);
      expect(merged.history.single.templateVersion, 1);
    });

    test("it survives the round trip to the database", () {
      const s = IntakeSubmission(answers: {"a": "b"}, at: "x", templateVersion: 3);
      expect(IntakeSubmission.fromJson(s.toJson()).templateVersion, 3);
    });

    test("a built-in form records no version", () {
      // Their questions live in code and change only with a release.
      const s = IntakeSubmission(answers: {"a": "b"}, at: "x");
      expect(s.toJson().containsKey("templateVersion"), isFalse);
      expect(IntakeSubmission.fromJson(s.toJson()).templateVersion, isNull);
    });
  });
}

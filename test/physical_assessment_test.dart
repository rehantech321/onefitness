import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/data/physical_assessment_schema.dart";

/// The coach-conducted Physical Assessment.
///
/// Two things have to hold. The keys must match the web app's
/// PHYSICAL_ASSESSMENT_SECTIONS exactly, because both apps write the same
/// `intake.physical` object and generate-ai-workout-program reads it. And an
/// assessment must survive a later save from anywhere else in the app —
/// those fields live beside `completed`, not inside `answers`, so anything
/// rebuilding the entry from known fields alone would erase them.
void main() {
  group("the movement screen matches the web spec", () {
    test("the eight sections are there, in order", () {
      expect(
        kPhysicalAssessmentSections.map((s) => s.key),
        ["postureMobility", "push", "pull", "squat", "hinge", "lunge", "carry", "core"],
      );
    });

    test("every movement key is unique", () {
      // A duplicate would make two movements share one Green/Yellow/Red
      // rating, and rating one would silently change the other.
      final keys = allPhysicalMovementKeys;
      expect(keys.toSet().length, keys.length);
    });

    test("the movement keys are the web's", () {
      expect(allPhysicalMovementKeys, [
        "toeTouchNarrow", "toeTouchWide", "shoulderMobility",
        "pushUps", "squatToPress",
        "bandPullAparts", "pullUp",
        "narrowSquat", "standardSquat", "wideSquat",
        "hipHinge",
        "walkingLunges",
        "suitcaseCarry",
        "walkouts", "plank",
      ]);
    });

    test("only Posture & Mobility carries the photo checklist", () {
      final withPhotos = kPhysicalAssessmentSections.where((s) => s.photoCheck);
      expect(withPhotos.map((s) => s.key), ["postureMobility"]);
      expect(kPhysicalPhotoAngles, ["Front", "Side", "Rear"]);
    });

    test("the sections with observations have them, and the others don't", () {
      final withObs = kPhysicalAssessmentSections.where((s) => s.observations.isNotEmpty).map((s) => s.key);
      expect(withObs, ["squat", "hinge", "lunge", "carry"]);
    });

    test("every section has at least one movement", () {
      for (final s in kPhysicalAssessmentSections) {
        expect(s.movements, isNotEmpty, reason: "${s.key} has nothing to rate");
      }
    });

    test("programming flags and program statuses match the web list", () {
      expect(kProgrammingFlags.length, 10);
      expect(kProgrammingFlags.first, "Shoulder Mobility");
      expect(kProgrammingFlags.last, "No Significant Restrictions");
      expect(kProgramStatusOptions.map((o) => o.$1), ["ready", "review", "medical"]);
    });
  });

  group("an assessment survives other saves", () {
    // The shape the web app writes and the AI drafter reads.
    final physicalPayload = <String, dynamic>{
      "scores": {"narrowSquat": "yellow", "plank": "green"},
      "observations": {
        "squat": ["Heel Lift", "Knee Cave"],
      },
      "painScreen": {"hadPain": "yes", "explain": "Left knee on the lunge"},
      "overall": {"primaryLimitation": "Ankle mobility", "secondaryLimitation": "", "strongestPattern": "Hinge"},
      "programmingFlags": ["Squat", "Lunge"],
      "coachSummary": "Strong hinge, limited ankles. Regress the squat.",
      "programStatus": "review",
      "photos": ["Front", "Side"],
      "notes": {"squat": "Box squat to start"},
    };

    test("extra keys are kept on the record", () {
      final record = IntakeRecord(completed: true, by: "Trainer/Coach", extra: physicalPayload);
      expect(record.extra["coachSummary"], contains("Strong hinge"));
      expect((record.extra["scores"] as Map)["narrowSquat"], "yellow");
      expect((record.extra["programmingFlags"] as List), contains("Squat"));
    });

    test("copyWith carries them through", () {
      // The path that would have destroyed them: attaching a file or
      // flipping completion rebuilds the record.
      final original = IntakeRecord(completed: true, extra: physicalPayload);
      final after = original.copyWith(attachments: const []);
      expect(after.extra["coachSummary"], original.extra["coachSummary"]);
      expect(after.extra["painScreen"], original.extra["painScreen"]);
    });

    test("the modelled fields are not swallowed into extra", () {
      // knownKeys is what splits the two. If "completed" leaked into extra,
      // the write would put a stale value back over the real one.
      //
      // "history" and "templateVersion" joined the list when a form gained
      // the ability to be filled in more than once — the earlier submissions
      // are modelled, not loose payload.
      expect(IntakeRecord.knownKeys, {
        "answers",
        "completed",
        "at",
        "by",
        "attachments",
        "history",
        "templateVersion",
      });
      for (final key in IntakeRecord.knownKeys) {
        expect(physicalPayload.containsKey(key), isFalse, reason: "$key would collide");
      }
    });

    test("a record with no assessment has an empty extra, not null", () {
      expect(const IntakeRecord().extra, isEmpty);
    });

    test("an unanswered pain screen is recorded as unanswered", () {
      // Written even when blank, so "not asked" reads differently from
      // "no pain" — which changes how a coach reads the assessment later.
      final blank = <String, dynamic>{"painScreen": {"hadPain": null, "explain": ""}};
      final record = IntakeRecord(completed: true, extra: blank);
      expect((record.extra["painScreen"] as Map).containsKey("hadPain"), isTrue);
      expect((record.extra["painScreen"] as Map)["hadPain"], isNull);
    });
  });
}

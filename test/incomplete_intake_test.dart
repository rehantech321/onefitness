import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/intake_entitlements.dart";
import "package:onefitness/core/utils/onboarding_utils.dart";
import "package:onefitness/data/models/booking.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_plan.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/data/models/membership_plan.dart";

/// Unfinished intake forms, and who hears about them.
///
/// Three surfaces have to agree on what "incomplete" means: the client's own
/// dashboard prompt, the alert their coach gets when they book, and the
/// marker beside their name in the session roster. They all read the same
/// helper, so these tests cover all three at once.
void main() {
  ClientRecord record({bool training = false, bool nutrition = false, bool physical = false}) =>
      ClientRecord(
        id: "c1",
        intake: {
          if (training) "personalTraining": const IntakeRecord(completed: true),
          if (nutrition) "nutritional": const IntakeRecord(completed: true),
          if (physical) "physical": const IntakeRecord(completed: true),
        },
      );

  group("which forms are outstanding", () {
    test("a brand-new client is missing both questionnaires", () {
      expect(incompleteIntakeTitles(record()), [
        "Personalized Training Intake",
        "Nutrition Program Intake",
      ]);
      expect(hasIncompleteIntake(record()), isTrue);
    });

    test("finishing one leaves the other", () {
      expect(incompleteIntakeTitles(record(training: true)), ["Nutrition Program Intake"]);
      expect(incompleteIntakeTitles(record(nutrition: true)), ["Personalized Training Intake"]);
    });

    test("finishing both clears it", () {
      final done = record(training: true, nutrition: true);
      expect(incompleteIntakeTitles(done), isEmpty);
      expect(hasIncompleteIntake(done), isFalse);
    });

    test("the physical assessment is not counted", () {
      // It's a session a coach conducts, not something a client can go and
      // finish — so chasing them for it would be chasing the wrong person.
      final done = record(training: true, nutrition: true);
      expect(incompleteIntakeTitles(done), isEmpty);
      expect(incompleteIntakeTitles(record(physical: true)).length, 2);
    });

    test("a started-but-unfinished form still counts as outstanding", () {
      const started = ClientRecord(
        id: "c1",
        intake: {"personalTraining": IntakeRecord(answers: {"goal": "Lose fat"})},
      );
      expect(incompleteIntakeTitles(started), contains("Personalized Training Intake"));
    });
  });

  group("the questionnaires are no longer behind a purchase", () {
    test("a client who has bought nothing can fill both", () {
      const none = IntakeEntitlements.none;
      expect(none.allows("personalTraining"), isTrue);
      expect(none.allows("nutritional"), isTrue);
    });

    test("the coach-run physical assessment still needs a membership or package", () {
      // Someone has to be paid to conduct it, so this one really is gated.
      expect(IntakeEntitlements.none.allows("physical"), isFalse);
      expect(const IntakeEntitlements(physical: true, hasAnyPurchase: true).allows("physical"), isTrue);
    });

    MembershipPlan plan(String id, PlanKind kind) =>
        MembershipPlan(id: id, name: id, kind: kind);

    ClientInfo holder(String planId) => ClientInfo(
          id: "c1",
          name: "Ahmad",
          plans: [ClientPlanEnrollment(planId: planId, status: "active", startDate: "2026-10-01")],
        );

    test("a membership or package unlocks the assessment", () {
      for (final kind in [PlanKind.membership, PlanKind.package]) {
        final e = computeIntakeEntitlements(
          info: holder("p"),
          allPlans: [plan("p", kind)],
        );
        expect(e.physical, isTrue, reason: "$kind should pay for the assessment");
        expect(e.hasAnyPurchase, isTrue);
      }
    });

    test("a program grants programming, not gym time", () {
      for (final kind in [PlanKind.program, PlanKind.nutritionProgram]) {
        final e = computeIntakeEntitlements(
          info: holder("p"),
          allPlans: [plan("p", kind)],
        );
        expect(e.physical, isFalse, reason: "$kind shouldn't unlock a coach-run session");
        // ...but it is still a purchase, so they aren't sent to the Access Hub.
        expect(e.hasAnyPurchase, isTrue);
      }
    });

    test("holding nothing is the only case with no purchase", () {
      final e = computeIntakeEntitlements(
        info: const ClientInfo(id: "c1", name: "Ahmad"),
        allPlans: const [],
      );
      expect(e.hasAnyPurchase, isFalse);
      expect(e.physical, isFalse);
    });
  });

  group("the dashboard prompt", () {
    test("still lists both forms for a client who has bought nothing", () {
      // This is what "remains on the dashboard until completed" rests on:
      // before, entitlements filtered these out entirely for such a client.
      final alerts = getOnboardingAlerts(
        record(),
        const <Booking>[],
        "c1",
        null,
        entitlements: IntakeEntitlements.none,
      );
      expect(
        alerts.map((s) => s.key),
        containsAll(["personalizedIntake", "nutritionIntake"]),
      );
    });

    test("drops a form as soon as it's completed, and keeps the other", () {
      final alerts = getOnboardingAlerts(
        record(training: true),
        const <Booking>[],
        "c1",
        null,
        entitlements: IntakeEntitlements.none,
      );
      expect(alerts.map((s) => s.key), isNot(contains("personalizedIntake")));
      expect(alerts.map((s) => s.key), contains("nutritionIntake"));
    });

    test("booking anything retires the assessment step", () {
      const booking = Booking(
        id: "b1",
        clientId: "c1",
        trainerId: "t1",
        date: "2026-11-02",
        slot: 540,
        sessionType: "one-on-one",
        discipline: "personal-training",
      );
      final alerts = getOnboardingAlerts(
        record(training: true, nutrition: true),
        const [booking],
        "c1",
        null,
        entitlements: IntakeEntitlements.none,
      );
      expect(alerts, isEmpty);
    });
  });
}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/plan_members.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_plan.dart";

/// "Who is on this plan" — the question the archive dialog already answered
/// with a number ("1 member(s) are on this plan") while giving the owner no
/// way to find out which person that was.
///
/// The trap: a client holds a plan two different ways. The primary slot is
/// the obvious one, but a client can also hold a plan alongside it — a
/// package bought on top of a membership — and checking only the slot would
/// quietly miss them.
void main() {
  ClientPlanEnrollment enrol(
    String planId, {
    String status = "active",
    String startDate = "2026-09-01",
    String? cancelsAt,
    String? endsAt,
  }) =>
      ClientPlanEnrollment(
        planId: planId,
        status: status,
        startDate: startDate,
        cancelsAt: cancelsAt,
        endsAt: endsAt,
      );

  ClientInfo client(
    String name, {
    String? membershipPlanId,
    List<ClientPlanEnrollment> plans = const [],
  }) =>
      ClientInfo(
        id: "id-$name",
        name: name,
        membershipPlanId: membershipPlanId,
        plans: plans,
      );

  group("finding who holds a plan", () {
    test("someone whose primary slot is this plan", () {
      final roster = [client("Tina", membershipPlanId: "p1")];
      expect(membersOnPlan(roster, "p1").map((c) => c.name), ["Tina"]);
    });

    test("someone holding it alongside another plan", () {
      // A package bought on top of a membership: the slot holds the
      // membership, so only the enrolment list shows this one.
      final roster = [
        client("Sam", membershipPlanId: "membership", plans: [enrol("p1")]),
      ];
      expect(membersOnPlan(roster, "p1").map((c) => c.name), ["Sam"]);
    });

    test("someone on a different plan entirely is not included", () {
      final roster = [client("Alex", membershipPlanId: "other")];
      expect(membersOnPlan(roster, "p1"), isEmpty);
    });

    test("a cancelled enrolment does not count — that is history, not access", () {
      final roster = [
        client("Jo", plans: [enrol("p1", status: "cancelled")]),
      ];
      expect(membersOnPlan(roster, "p1"), isEmpty);
    });

    test("holding it both ways lists the person once, not twice", () {
      final roster = [
        client("Dana", membershipPlanId: "p1", plans: [enrol("p1")]),
      ];
      expect(membersOnPlan(roster, "p1").length, 1);
    });

    test("names come out in alphabetical order", () {
      final roster = [
        client("Zoe", membershipPlanId: "p1"),
        client("adam", membershipPlanId: "p1"),
        client("Mia", membershipPlanId: "p1"),
      ];
      // Case-insensitive, or a lowercase name would sort to the bottom.
      expect(membersOnPlan(roster, "p1").map((c) => c.name), ["adam", "Mia", "Zoe"]);
    });

    test("an empty roster is not an error", () {
      expect(membersOnPlan(const [], "p1"), isEmpty);
    });

    test("the count matches what the archive dialog reports", () {
      final roster = [
        client("Tina", membershipPlanId: "p1"),
        client("Sam", plans: [enrol("p1")]),
        client("Alex", membershipPlanId: "other"),
      ];
      expect(membersOnPlan(roster, "p1").length, 2);
    });
  });

  group("how someone holds it", () {
    test("primary when it occupies their slot", () {
      final c = client("Tina", membershipPlanId: "p1");
      expect(isPrimaryPlan(c, "p1"), isTrue);
    });

    test("additional when they hold it alongside another", () {
      final c = client("Sam", membershipPlanId: "membership", plans: [enrol("p1")]);
      expect(isPrimaryPlan(c, "p1"), isFalse);
    });
  });

  group("when they started", () {
    test("taken from the enrolment", () {
      final c = client("Tina", plans: [enrol("p1", startDate: "2026-08-14")]);
      expect(planStartDate(c, "p1"), "2026-08-14");
    });

    test("null for a plan assigned without an enrolment record", () {
      // A coach assigning a plan writes the slot but no enrolment entry.
      final c = client("Tina", membershipPlanId: "p1");
      expect(planStartDate(c, "p1"), isNull);
    });

    test("a blank date reads as unknown rather than an empty label", () {
      final c = client("Tina", plans: [enrol("p1", startDate: "  ")]);
      expect(planStartDate(c, "p1"), isNull);
    });
  });

  group("when it is due to end", () {
    test("a cancelled-but-still-running plan reports its end date", () {
      // They are on it today and will not be shortly — worth seeing in a
      // list of who currently has access.
      final c = client("Tina", plans: [enrol("p1", cancelsAt: "2026-11-01")]);
      expect(planEndsOn(c, "p1"), "2026-11-01");
    });

    test("a plan simply running normally has nothing to report", () {
      final c = client("Tina", plans: [enrol("p1")]);
      expect(planEndsOn(c, "p1"), isNull);
    });

    test("an explicit end date is used when there is no cancellation", () {
      final c = client("Tina", plans: [enrol("p1", endsAt: "2026-12-31")]);
      expect(planEndsOn(c, "p1"), "2026-12-31");
    });

    test("a cancellation date takes precedence over the end date", () {
      final c = client("Tina", plans: [enrol("p1", cancelsAt: "2026-11-01", endsAt: "2026-12-31")]);
      expect(planEndsOn(c, "p1"), "2026-11-01");
    });
  });
}

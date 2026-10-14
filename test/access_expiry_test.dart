import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/membership_utils.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_plan.dart";
import "package:onefitness/data/models/membership_plan.dart";

/// Access granted with an end date has to actually stop on that date.
///
/// The enrolment list was already filtered by it, but the plan in the
/// client's primary slot was added unconditionally — so an expiry set on
/// someone's main membership did nothing, and they kept booking forever.
/// That is the failure these guard against: a date that looks set and isn't
/// enforced is worse than no date at all.
void main() {
  const membership = MembershipPlan(
    id: "p-mem",
    name: "8 Sessions / Month",
    kind: PlanKind.membership,
    priceCents: 48000,
    maxSessions: 8,
  );
  const pack = MembershipPlan(
    id: "p-pack",
    name: "10 Session Package",
    kind: PlanKind.package,
    priceCents: 60000,
    maxSessions: 10,
  );
  const catalogue = [membership, pack];

  String daysFromNow(int days) =>
      DateTime.now().add(Duration(days: days)).toIso8601String().substring(0, 10);

  ClientPlanEnrollment enrol(String planId, {String? endsAt, String status = "active"}) =>
      ClientPlanEnrollment(
        planId: planId,
        status: status,
        startDate: "2026-09-01",
        endsAt: endsAt,
      );

  ClientInfo client({String? slot, List<ClientPlanEnrollment> plans = const []}) =>
      ClientInfo(id: "c1", name: "Tina", membershipPlanId: slot, plans: plans);

  List<String> heldIds(ClientInfo c) =>
      heldAccessPlans(c, catalogue).map((p) => p.id).toList();

  group("the plan in the primary slot", () {
    test("is held when it has no expiry", () {
      expect(heldIds(client(slot: "p-mem")), ["p-mem"]);
    });

    test("is held while its expiry is still ahead", () {
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem", endsAt: daysFromNow(30))],
      );
      expect(heldIds(c), ["p-mem"]);
    });

    test("is NOT held once its expiry has passed", () {
      // The bug: this used to come back held regardless, so "access until
      // March" let someone book in June.
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem", endsAt: daysFromNow(-1))],
      );
      expect(heldIds(c), isEmpty);
    });

    test("is held on the expiry day itself", () {
      // Access runs to the end of the day it expires, not up to it.
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem", endsAt: daysFromNow(0))],
      );
      expect(heldIds(c), ["p-mem"]);
    });

    test("an expiry on a different plan doesn't affect it", () {
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-pack", endsAt: daysFromNow(-5))],
      );
      expect(heldIds(c), contains("p-mem"));
    });

    test("a cancelled enrolment for the slot plan doesn't expire it", () {
      // Only an active enrolment's date is the one in force; a cancelled
      // row is history and must not revoke a plan the client still holds.
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem", endsAt: daysFromNow(-5), status: "cancelled")],
      );
      expect(heldIds(c), ["p-mem"]);
    });
  });

  group("extra plans held alongside", () {
    test("a package with a future expiry is held", () {
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem"), enrol("p-pack", endsAt: daysFromNow(60))],
      );
      expect(heldIds(c), containsAll(["p-mem", "p-pack"]));
    });

    test("an expired package drops out while the membership stays", () {
      final c = client(
        slot: "p-mem",
        plans: [enrol("p-mem"), enrol("p-pack", endsAt: daysFromNow(-1))],
      );
      expect(heldIds(c), ["p-mem"]);
    });

    test("everything expiring leaves nothing held", () {
      final c = client(
        slot: "p-mem",
        plans: [
          enrol("p-mem", endsAt: daysFromNow(-10)),
          enrol("p-pack", endsAt: daysFromNow(-3)),
        ],
      );
      expect(heldIds(c), isEmpty);
    });
  });

  group("order is unchanged by expiry", () {
    test("the membership still comes before packages", () {
      // Booking draws on the membership first because its sessions reset
      // monthly; adding expiry must not have disturbed that.
      final c = client(
        slot: "p-pack",
        plans: [enrol("p-pack"), enrol("p-mem", endsAt: daysFromNow(30))],
      );
      expect(heldIds(c), ["p-mem", "p-pack"]);
    });
  });

  group("a plan no longer in the catalogue", () {
    test("is simply not held, rather than crashing the booking screen", () {
      final c = client(slot: "gone", plans: [enrol("gone")]);
      expect(heldIds(c), isEmpty);
    });
  });
}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/membership_utils.dart";
import "package:onefitness/data/models/membership_plan.dart";

/// A plan's sales window, and what its session allowance means.
///
/// The window governs **selling only**: outside it a plan can't be bought or
/// assigned and drops out of the Access Hub, while everyone already on it
/// keeps their access, their allowance and their bookings. Getting that
/// backwards would cut off paying members on a date set months earlier.
void main() {
  MembershipPlan plan({String? start, String? end, PlanKind kind = PlanKind.package}) =>
      MembershipPlan(id: "p", name: "8 Semi-Private", kind: kind, startDate: start, endDate: end);

  group("when a plan is on sale", () {
    test("no dates means always", () {
      expect(planOnSale(plan(), "2026-11-01"), isTrue);
      expect(planOnSale(plan(), "2001-01-01"), isTrue);
    });

    test("before the start date it isn't", () {
      expect(planOnSale(plan(start: "2026-12-01"), "2026-11-30"), isFalse);
    });

    test("the start date itself counts", () {
      expect(planOnSale(plan(start: "2026-12-01"), "2026-12-01"), isTrue);
    });

    test("the end date itself counts", () {
      // "On sale until 31 Dec" has to include the 31st, or every plan
      // closes a day early.
      expect(planOnSale(plan(end: "2026-12-31"), "2026-12-31"), isTrue);
    });

    test("after the end date it isn't", () {
      expect(planOnSale(plan(end: "2026-12-31"), "2027-01-01"), isFalse);
    });

    test("a window closes at both ends", () {
      final seasonal = plan(start: "2026-06-01", end: "2026-08-31");
      expect(planOnSale(seasonal, "2026-05-31"), isFalse);
      expect(planOnSale(seasonal, "2026-06-01"), isTrue);
      expect(planOnSale(seasonal, "2026-07-15"), isTrue);
      expect(planOnSale(seasonal, "2026-08-31"), isTrue);
      expect(planOnSale(seasonal, "2026-09-01"), isFalse);
    });

    test("a one-day window works", () {
      final oneDay = plan(start: "2026-11-11", end: "2026-11-11");
      expect(planOnSale(oneDay, "2026-11-11"), isTrue);
      expect(planOnSale(oneDay, "2026-11-10"), isFalse);
      expect(planOnSale(oneDay, "2026-11-12"), isFalse);
    });

    test("blank strings are treated as no date, not as a boundary", () {
      // The editor clears a date to "", not null.
      expect(planOnSale(plan(start: "", end: ""), "2026-11-01"), isTrue);
      expect(planOnSale(plan(start: "   "), "2026-11-01"), isTrue);
    });

    test("the window applies to memberships as well as packages", () {
      // It was packages-only before: `isSub` dropped a membership's start
      // date on save and hid the expiry toggle entirely.
      final m = plan(start: "2026-06-01", end: "2026-08-31", kind: PlanKind.membership);
      expect(planOnSale(m, "2026-05-01"), isFalse);
      expect(planOnSale(m, "2026-07-01"), isTrue);
      expect(planOnSale(m, "2026-09-01"), isFalse);
    });
  });

  group("what the session allowance is called", () {
    test("a membership's number is per month", () {
      expect(sessionAllowanceLabel(PlanKind.membership), "Sessions per month");
    });

    test("a package's number is the whole allowance", () {
      // The editor just said "Max sessions", which is true of both and
      // explains neither — and the two really do mean different things:
      // a membership resets monthly, a package counts down to nothing.
      expect(sessionAllowanceLabel(PlanKind.package), "Sessions included");
      expect(sessionAllowanceLabel(PlanKind.program), "Sessions included");
    });
  });
}

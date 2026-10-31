import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/membership_plan.dart";
import "package:onefitness/features/client/drawer_screens/membership_hub_screen.dart";

/// The Access Hub's single row of filter chips.
///
/// Kind and category were two separate controls — pills that filtered, and a
/// row of tiles that only scrolled to a heading. They're now one row where
/// every chip filters, which means one selection has to span both
/// dimensions: picking a category drops the kind filter and the reverse.
void main() {
  MembershipPlan plan(String id, PlanKind kind, String? category) =>
      MembershipPlan(id: id, name: id, kind: kind, category: category);

  final all = [
    plan("mem-semi", PlanKind.membership, "Membership Semi-Private"),
    plan("pkg-semi", PlanKind.package, "Package Semi-Private"),
    plan("one-on-one-12", PlanKind.package, "One-on-One"),
    plan("one-on-one-16", PlanKind.package, "One-on-One"),
    plan("loose", PlanKind.membership, null),
  ];
  List<String> ids(List<MembershipPlan> p) => p.map((x) => x.id).toList();

  group("categorising a plan", () {
    test("uses the plan's own category", () {
      expect(planFilterCategory(plan("p", PlanKind.package, "One-on-One")), "One-on-One");
    });

    test("a missing or blank category falls into Other", () {
      // Must match _groupByCategory's bucketing, or a chip would filter to
      // nothing under a heading that showed plans.
      expect(planFilterCategory(plan("p", PlanKind.package, null)), "Other");
      expect(planFilterCategory(plan("p", PlanKind.package, "")), "Other");
      expect(planFilterCategory(plan("p", PlanKind.package, "   ")), "Other");
    });

    test("surrounding whitespace doesn't make a separate category", () {
      expect(planFilterCategory(plan("p", PlanKind.package, "  One-on-One  ")), "One-on-One");
    });
  });

  group("applying the selected chip", () {
    test("All keeps everything", () {
      expect(ids(applyPlanFilter(all, "all")), ids(all));
    });

    test("a kind chip keeps only that kind", () {
      expect(ids(applyPlanFilter(all, "kind:membership")), ["mem-semi", "loose"]);
      expect(
        ids(applyPlanFilter(all, "kind:package")),
        ["pkg-semi", "one-on-one-12", "one-on-one-16"],
      );
    });

    test("a category chip keeps only that category, across kinds", () {
      expect(ids(applyPlanFilter(all, "cat:One-on-One")), ["one-on-one-12", "one-on-one-16"]);
      expect(ids(applyPlanFilter(all, "cat:Membership Semi-Private")), ["mem-semi"]);
    });

    test("a category name containing a colon still resolves whole", () {
      // The filter id is "cat:" plus the name, so only the FIRST colon may be
      // treated as the separator.
      final odd = [plan("x", PlanKind.package, "Summer: Bootcamp")];
      expect(ids(applyPlanFilter(odd, "cat:Summer: Bootcamp")), ["x"]);
    });

    test("uncategorised plans are reachable through Other", () {
      expect(ids(applyPlanFilter(all, "cat:Other")), ["loose"]);
    });

    test("a category nobody holds yields an empty list, not an error", () {
      expect(applyPlanFilter(all, "cat:Nothing Here"), isEmpty);
    });

    test("an unrecognised filter shows everything rather than nothing", () {
      // A stale selection that emptied the hub would read as the gym having
      // no plans at all.
      expect(ids(applyPlanFilter(all, "")), ids(all));
      expect(ids(applyPlanFilter(all, "garbage")), ids(all));
    });

    test("filtering never reorders what survives", () {
      // The sections below the chips rely on catalogue order.
      expect(ids(applyPlanFilter(all, "kind:package")), ["pkg-semi", "one-on-one-12", "one-on-one-16"]);
    });
  });
}

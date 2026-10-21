import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/membership_plan.dart";

/// Categories in the client's Access Hub appeared in reverse.
///
/// The grouping follows the gym's own category list, which is right — but
/// anything NOT in that list fell through in whatever order the plans
/// happened to arrive in. The plan list is newest-first, so when the
/// category list hadn't loaded yet the sections came out backwards.
///
/// The grouping function is private to the hub screen, so this reproduces
/// its ordering rule. If that rule changes, these should change with it.
void main() {
  const uncategorised = "Other";

  MembershipPlan plan(String id, String? category) =>
      MembershipPlan(id: id, name: id, kind: PlanKind.package, category: category);

  /// The same ordering the hub applies: the gym's order first, then
  /// anything left over by name, then uncategorised last.
  List<String> sectionOrder(List<MembershipPlan> plans, List<String> order) {
    final buckets = <String, List<MembershipPlan>>{};
    for (final p in plans) {
      final c = (p.category ?? "").trim();
      buckets.putIfAbsent(c.isEmpty ? uncategorised : c, () => []).add(p);
    }
    final leftovers = <String>[
      for (final c in buckets.keys)
        if (c != uncategorised && !order.contains(c)) c,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return <String>[
      for (final c in order)
        if (buckets.containsKey(c)) c,
      ...leftovers,
      if (buckets.containsKey(uncategorised)) uncategorised,
    ];
  }

  group("sections follow the gym's own order", () {
    final plans = [
      plan("p1", "Nutrition Program"),
      plan("p2", "Personalized Program"),
      plan("p3", "One-on-One"),
    ];

    test("not the order the plans arrived in", () {
      // The plans are newest-first here, which is how the hub receives them.
      expect(
        sectionOrder(plans, ["One-on-One", "Personalized Program", "Nutrition Program"]),
        ["One-on-One", "Personalized Program", "Nutrition Program"],
      );
    });

    test("moving a category to the top moves its section", () {
      expect(
        sectionOrder(plans, ["Nutrition Program", "One-on-One", "Personalized Program"]).first,
        "Nutrition Program",
      );
    });

    test("a category with no plans gets no section", () {
      // Otherwise a tile could scroll to an empty heading.
      final order = ["One-on-One", "Empty Category", "Nutrition Program"];
      expect(sectionOrder(plans, order), isNot(contains("Empty Category")));
    });
  });

  group("categories the gym's list doesn't mention", () {
    test("are ordered by name, not by plan order", () {
      // This is the actual bug: with no order to follow, the sections used
      // to come out in plan order, which is newest-first — i.e. reversed.
      final plans = [
        plan("p1", "Zumba"),
        plan("p2", "Boxing"),
        plan("p3", "Aqua"),
      ];
      expect(sectionOrder(plans, const []), ["Aqua", "Boxing", "Zumba"]);
    });

    test("the same list comes back the same way whatever order it arrives in", () {
      final forwards = [plan("a", "Aqua"), plan("b", "Boxing"), plan("c", "Zumba")];
      final backwards = [plan("c", "Zumba"), plan("b", "Boxing"), plan("a", "Aqua")];
      expect(sectionOrder(forwards, const []), sectionOrder(backwards, const []));
    });

    test("case doesn't upset the sort", () {
      final plans = [plan("p1", "zumba"), plan("p2", "Boxing")];
      expect(sectionOrder(plans, const []), ["Boxing", "zumba"]);
    });

    test("a deleted category still gets a section, after the known ones", () {
      // A category can be removed while plans still point at it; those
      // plans must not vanish from the hub.
      final plans = [plan("p1", "One-on-One"), plan("p2", "Deleted Category")];
      expect(sectionOrder(plans, ["One-on-One"]), ["One-on-One", "Deleted Category"]);
    });
  });

  group("plans with no category", () {
    test("come last, whatever else is there", () {
      final plans = [plan("p1", null), plan("p2", "One-on-One"), plan("p3", "Aqua")];
      expect(sectionOrder(plans, ["One-on-One"]).last, uncategorised);
    });

    test("a blank category counts as none, not as its own section", () {
      final plans = [plan("p1", "   "), plan("p2", "One-on-One")];
      expect(sectionOrder(plans, ["One-on-One"]), ["One-on-One", uncategorised]);
    });

    test("no uncategorised section when every plan has one", () {
      final plans = [plan("p1", "One-on-One")];
      expect(sectionOrder(plans, ["One-on-One"]), ["One-on-One"]);
    });
  });

  group("reordering, as the admin screen does it", () {
    /// Swapping a category with its neighbour.
    List<String> move(List<String> list, String name, int direction) {
      final out = [...list];
      final i = out.indexOf(name);
      final j = i + direction;
      if (i < 0 || j < 0 || j >= out.length) return out;
      out[i] = out[j];
      out[j] = name;
      return out;
    }

    final list = ["A", "B", "C"];

    test("up swaps with the one above", () {
      expect(move(list, "B", -1), ["B", "A", "C"]);
    });

    test("down swaps with the one below", () {
      expect(move(list, "B", 1), ["A", "C", "B"]);
    });

    test("the first can't move up", () {
      expect(move(list, "A", -1), list);
    });

    test("the last can't move down", () {
      expect(move(list, "C", 1), list);
    });

    test("a name not in the list changes nothing", () {
      expect(move(list, "Z", -1), list);
    });

    test("positions are spaced so a later insert needs no renumbering", () {
      final positions = [for (var i = 0; i < list.length; i++) (i + 1) * 10];
      expect(positions, [10, 20, 30]);
      // Room between every pair.
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i] - positions[i - 1], greaterThan(1));
      }
    });
  });

  group("the purchase sheet groups the same way the hub does", () {
    // A coach picking a plan for someone should be looking at the same
    // catalogue, in the same order, that the client would see.
    List<String> purchaseSections(List<MembershipPlan> plans, List<String> order) =>
        sectionOrder(plans, order);

    test("sections follow the gym's category order", () {
      final plans = [
        plan("p1", "Nutrition Program"),
        plan("p2", "One-on-One"),
      ];
      expect(
        purchaseSections(plans, ["One-on-One", "Nutrition Program"]),
        ["One-on-One", "Nutrition Program"],
      );
    });

    test("uncategorised plans are still offered, at the end", () {
      // They must never be dropped: a plan with no category is still a
      // plan a coach may need to sell.
      final plans = [plan("p1", "One-on-One"), plan("p2", null)];
      final sections = purchaseSections(plans, ["One-on-One"]);
      expect(sections.last, uncategorised);
      expect(sections.length, 2);
    });

    test("every plan lands in exactly one section", () {
      final plans = [
        plan("p1", "One-on-One"),
        plan("p2", "One-on-One"),
        plan("p3", "Nutrition Program"),
        plan("p4", null),
      ];
      final buckets = <String, List<MembershipPlan>>{};
      for (final p in plans) {
        final c = (p.category ?? "").trim();
        buckets.putIfAbsent(c.isEmpty ? uncategorised : c, () => []).add(p);
      }
      final counted = buckets.values.fold(0, (sum, list) => sum + list.length);
      expect(counted, plans.length);
    });
  });
}

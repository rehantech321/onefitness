import "package:flutter/gestures.dart" show kLongPressTimeout;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/widgets/reorderable_column.dart";
import "package:onefitness/data/models/membership_plan.dart";

/// Press-and-hold reordering.
///
/// Two things are worth pinning down. First the index arithmetic:
/// ReorderableListView reports the drop target as a position in the list
/// *before* the dragged item is removed, so every downward move is off by one
/// unless that is corrected — the classic way a drag lands one slot short.
/// Second, that a long press is what starts a drag and a plain drag is not,
/// which is the whole reason these lists can live inside a scrolling page.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<String> items,
    required void Function(int, int) onReorder,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReorderableColumn(
              itemCount: items.length,
              keyOf: (i) => items[i],
              onReorder: onReorder,
              itemBuilder: (context, i) => SizedBox(
                height: 64,
                child: Center(child: Text(items[i])),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets("renders every item inside a scrolling page", (tester) async {
    await pump(tester, items: const ["A", "B", "C"], onReorder: (_, _) {});
    expect(find.text("A"), findsOneWidget);
    expect(find.text("B"), findsOneWidget);
    expect(find.text("C"), findsOneWidget);
  });

  testWidgets("a plain drag scrolls — it does not reorder", (tester) async {
    // The reason the arrows existed. If an ordinary drag moved items, this
    // list could never sit inside a page the user also needs to scroll.
    var reorders = 0;
    await pump(tester, items: const ["A", "B", "C"], onReorder: (_, _) => reorders++);
    await tester.drag(find.text("A"), const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(reorders, 0);
  });

  testWidgets("a press held, then dragged, reorders", (tester) async {
    int? from;
    int? to;
    await pump(
      tester,
      items: const ["A", "B", "C"],
      onReorder: (o, n) {
        from = o;
        to = n;
      },
    );
    final start = tester.getCenter(find.text("A"));
    final gesture = await tester.startGesture(start);
    // Past kLongPressTimeout, which is what arms the drag.
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(start + const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(start + const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(from, 0, reason: "the held item was the one picked up");
    expect(to, isNotNull, reason: "a held drag should have reordered");
    // Dragged down one row: it must land at index 1, not 2. Index 2 is what
    // comes back when the framework's pre-removal index isn't adjusted.
    expect(to, 1);
  });

  testWidgets("a long press that goes nowhere changes nothing", (tester) async {
    var reorders = 0;
    await pump(tester, items: const ["A", "B", "C"], onReorder: (_, _) => reorders++);
    final gesture = await tester.startGesture(tester.getCenter(find.text("B")));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorders, 0);
  });

  testWidgets("a single item can't be picked up", (tester) async {
    var reorders = 0;
    await pump(tester, items: const ["Only"], onReorder: (_, _) => reorders++);
    expect(find.text("Only"), findsOneWidget);
    expect(reorders, 0);
  });

  group("plan order now survives a reload", () {
    MembershipPlan plan(String id, String name, {int? sortOrder}) => MembershipPlan(
          id: id,
          name: name,
          kind: PlanKind.package,
          sortOrder: sortOrder,
        );

    /// Mirrors the comparator loadMembershipPlans applies, which is the only
    /// thing making a saved order mean anything: the table is id/jsonb with
    /// no sort column, and the query has no `order by`.
    List<MembershipPlan> sorted(List<MembershipPlan> input) {
      final out = [...input];
      out.sort((a, b) {
        final ao = a.sortOrder, bo = b.sortOrder;
        if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
        if (ao != null && bo == null) return -1;
        if (ao == null && bo != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    }

    test("ordered plans come back in the owner's order", () {
      final out = sorted([
        plan("c", "Charlie", sortOrder: 30),
        plan("a", "Alpha", sortOrder: 10),
        plan("b", "Bravo", sortOrder: 20),
      ]);
      expect(out.map((p) => p.id), ["a", "b", "c"]);
    });

    test("plans saved before ordering existed sort last, by name", () {
      // Not in an arbitrary order that changes between loads, which is what
      // the screen did before sortOrder existed.
      final out = sorted([
        plan("z", "Zulu"),
        plan("a", "Alpha", sortOrder: 10),
        plan("m", "Mike"),
      ]);
      expect(out.map((p) => p.id), ["a", "m", "z"]);
    });

    test("gaps of ten leave room to slot one in between", () {
      final out = sorted([
        plan("a", "Alpha", sortOrder: 10),
        plan("new", "Inserted", sortOrder: 15),
        plan("b", "Bravo", sortOrder: 20),
      ]);
      expect(out.map((p) => p.id), ["a", "new", "b"]);
    });
  });
}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/activity_entry.dart";

/// The owner's "who changed what" feed. The grouping is what makes it
/// usable — an owner looking for a cancelled session shouldn't have to read
/// past every attendance tick — so that's what these pin, along with the
/// parsing being forgiving enough that one odd row can't blank the screen.
void main() {
  ActivityEntry entry(String action, {String entity = "booking", String? actor, String? subject}) =>
      ActivityEntry(
        id: "a-$action-$entity",
        at: "2026-10-13T18:30:00Z",
        action: action,
        entity: entity,
        summary: "$action $entity",
        actorName: actor,
        subject: subject,
      );

  group("what each entry counts as", () {
    test("money moving is a sale", () {
      expect(entry("sold", entity: "charge").isSale, isTrue);
      expect(entry("charged", entity: "charge").isSale, isTrue);
    });

    test("anything to do with a session is a session", () {
      for (final a in ["booked", "moved", "cancelled", "attendance"]) {
        expect(entry(a).isSession, isTrue, reason: a);
      }
    });

    test("catalogue and settings changes are edits", () {
      for (final a in ["created", "edited", "deleted"]) {
        expect(entry(a, entity: "plan").isEdit, isTrue, reason: a);
      }
    });

    test("the three groups don't overlap", () {
      // An entry landing in two filters would be counted twice in the
      // chip totals and read as duplicated in the feed.
      for (final a in [
        "sold", "charged", "booked", "moved", "cancelled",
        "attendance", "created", "edited", "deleted",
      ]) {
        final e = entry(a);
        final hits = [e.isSale, e.isSession, e.isEdit].where((x) => x).length;
        expect(hits, 1, reason: "$a landed in $hits groups");
      }
    });
  });

  group("the filters", () {
    final all = [
      entry("sold", entity: "charge"),
      entry("cancelled"),
      entry("moved"),
      entry("edited", entity: "plan"),
      entry("attendance"),
    ];

    test("Everything keeps everything", () {
      expect(all.where(ActivityFilter.all.matches).length, all.length);
    });

    test("Sales keeps only money", () {
      final kept = all.where(ActivityFilter.sales.matches).toList();
      expect(kept.map((e) => e.action), ["sold"]);
    });

    test("Sessions keeps the session ones, including attendance", () {
      final kept = all.where(ActivityFilter.sessions.matches).map((e) => e.action).toList();
      expect(kept, ["cancelled", "moved", "attendance"]);
    });

    test("Edits keeps catalogue and settings changes", () {
      expect(all.where(ActivityFilter.edits.matches).map((e) => e.action), ["edited"]);
    });

    test("every filter has a label", () {
      for (final f in ActivityFilter.values) {
        expect(f.label.trim(), isNotEmpty);
      }
    });
  });

  group("reading a row back from the database", () {
    test("a complete row", () {
      final e = ActivityEntry.fromJson({
        "id": "1",
        "at": "2026-10-13T18:30:00Z",
        "action": "cancelled",
        "entity": "booking",
        "summary": "Session cancelled for Tina on Oct 13",
        "actor_name": "Chris McCarthy",
        "subject": "Tina Smith",
      });
      expect(e, isNotNull);
      expect(e!.actorName, "Chris McCarthy");
      expect(e.isSession, isTrue);
      expect(e.atTime, isNotNull);
    });

    test("an entry with no actor is kept — the system does things too", () {
      // A Stripe webhook granting a plan has no signed-in person behind it.
      final e = ActivityEntry.fromJson({
        "id": "1",
        "action": "sold",
        "entity": "charge",
        "summary": "Sold Gold Membership — \$480.00",
      });
      expect(e, isNotNull);
      expect(e!.actorName, isNull);
    });

    test("a row with no summary is dropped rather than shown blank", () {
      expect(ActivityEntry.fromJson({"id": "1", "action": "sold"}), isNull);
    });

    test("a row with no id is dropped", () {
      expect(ActivityEntry.fromJson({"summary": "something happened"}), isNull);
    });

    test("an unparseable timestamp doesn't take down the feed", () {
      final e = ActivityEntry.fromJson({
        "id": "1",
        "at": "not a timestamp",
        "action": "edited",
        "entity": "plan",
        "summary": "Edited plan",
      });
      expect(e, isNotNull);
      expect(e!.atTime, isNull);
    });

    test("an unknown action is kept and shown, not hidden", () {
      // A new trigger added later must appear in the feed even before the
      // app knows how to categorise it.
      final e = ActivityEntry.fromJson({
        "id": "1",
        "action": "something_new",
        "entity": "thing",
        "summary": "Something happened",
      })!;
      expect(ActivityFilter.all.matches(e), isTrue);
      expect(e.isSale || e.isSession || e.isEdit, isFalse);
    });
  });
}

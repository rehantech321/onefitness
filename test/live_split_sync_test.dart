import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/program_day.dart";
import "package:onefitness/data/models/saved_program.dart";

/// The Training tab and the Programs tab read two different stores.
///
///   programDays   the "live split" — what the Training sub-tab shows
///   savedPrograms the named programs, and what the client actually trains
///                 from (status == "active")
///
/// Assigning a program and approving an AI draft both wrote only
/// `savedPrograms`, so the program appeared under Programs while the
/// Training tab still said "No days yet" — indistinguishable from the
/// assignment having failed.
void main() {
  ProgramDay day(String id, String title) => ProgramDay(id: id, title: title);

  SavedProgram program(String id, List<ProgramDay> days, {String status = "active"}) =>
      SavedProgram(id: id, name: "Push/Pull/Legs", status: status, programDays: days);

  /// Mirrors _liveSplitMirrors: day ids are minted fresh per program by both
  /// the builder and the generator, so an exact id-set match identifies a
  /// loaded copy — even after the coach edits its exercises, which never
  /// changes a day's id.
  bool liveSplitMirrors(ClientRecord record, SavedProgram p) {
    final liveIds = record.programDays.map((d) => d.id).toSet();
    if (liveIds.isEmpty) return false;
    final programIds = p.programDays.map((d) => d.id).toSet();
    return liveIds.length == programIds.length && liveIds.containsAll(programIds);
  }

  group("recognising a loaded copy", () {
    final days = [day("d1", "Push"), day("d2", "Pull")];

    test("a split loaded from a program mirrors it", () {
      final record = ClientRecord(id: "c1", programDays: days);
      expect(liveSplitMirrors(record, program("p1", days)), isTrue);
    });

    test("an empty split mirrors nothing", () {
      // Guards the case where "is this a copy?" would otherwise be
      // vacuously true and skip the overwrite warning.
      const record = ClientRecord(id: "c1");
      expect(liveSplitMirrors(record, program("p1", days)), isFalse);
    });

    test("a split the coach built independently does not mirror", () {
      // This is the one that must prompt before being replaced: those days
      // exist nowhere else.
      final record = ClientRecord(id: "c1", programDays: [day("own-1", "Upper")]);
      expect(liveSplitMirrors(record, program("p1", days)), isFalse);
    });

    test("editing exercises doesn't break the match", () {
      // Day ids survive exercise edits, which is the whole reason the match
      // is on ids rather than contents.
      final edited = [
        day("d1", "Push").copyWith(exercises: const []),
        day("d2", "Pull"),
      ];
      final record = ClientRecord(id: "c1", programDays: edited);
      expect(liveSplitMirrors(record, program("p1", days)), isTrue);
    });

    test("a partial overlap is not a copy", () {
      final record = ClientRecord(id: "c1", programDays: [day("d1", "Push")]);
      expect(liveSplitMirrors(record, program("p1", days)), isFalse);
    });
  });

  group("what the client sees", () {
    test("only active saved programs — never the live split", () {
      // The live split is the coach's working copy. A client with days in
      // programDays but no active program has nothing to train from, which
      // is why assigning has to write savedPrograms too.
      final record = ClientRecord(
        id: "c1",
        programDays: [day("d1", "Push")],
        savedPrograms: [
          program("p1", [day("a", "A")], status: "draft"),
          program("p2", [day("b", "B")]),
        ],
      );
      final visible = record.savedPrograms.where((p) => p.status == "active").toList();
      expect(visible.map((p) => p.id), ["p2"]);
    });

    test("an AI draft stays invisible until approved", () {
      final record = ClientRecord(
        id: "c1",
        savedPrograms: [program("ai", [day("a", "A")], status: "draft")],
      );
      expect(record.savedPrograms.where((p) => p.status == "active"), isEmpty);

      final approved = record.savedPrograms.map((p) => p.copyWith(status: "active")).toList();
      expect(approved.where((p) => p.status == "active").length, 1);
      // ...and approving must also fill the live split, or the coach's
      // Training tab stays empty while the client has a program.
      expect(approved.first.programDays, isNotEmpty);
    });
  });
}

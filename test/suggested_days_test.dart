import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/program_utils.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/program_day.dart";
import "package:onefitness/data/models/saved_program.dart";
import "package:onefitness/data/models/workout_log.dart";

/// Committed vs suggested days, on the Flutter side.
///
/// The counts themselves are decided in the edge function (and tested there,
/// against its own module). What has to hold here is that the distinction
/// survives: that a day written before suggested days existed still reads as
/// committed, that editing a program can't quietly reclassify a day, and that
/// the two kinds are counted separately wherever a number is shown.
void main() {
  const committed = ProgramDay(id: "d1", title: "Upper A");
  const suggested = ProgramDay(
    id: "d2",
    title: "Easy aerobic run",
    suggested: true,
    rationale: "Builds the aerobic base her HYROX run legs depend on.",
  );

  group("ProgramDay", () {
    test("a day is committed unless it says otherwise", () {
      // Every program written before this feature existed has no kind at all.
      // Reading those as suggested would relabel clients' existing training
      // as optional.
      expect(committed.suggested, isFalse);
      expect(committed.rationale, isNull);
    });

    test("a suggested day carries its reason", () {
      expect(suggested.suggested, isTrue);
      expect(suggested.rationale, contains("HYROX"));
    });

    test("copyWith keeps the kind when exercises change", () {
      // The client's session logger calls copyWith to attach notes. If that
      // dropped the flag, logging against a suggested day would turn it into
      // a committed one.
      final edited = suggested.copyWith(exercises: const []);
      expect(edited.suggested, isTrue);
      expect(edited.rationale, suggested.rationale);

      final editedCommitted = committed.copyWith(exercises: const []);
      expect(editedCommitted.suggested, isFalse);
    });
  });

  group("SavedProgram", () {
    const program = SavedProgram(
      id: "p1",
      name: "Marine - (3) per week",
      source: "ai",
      status: "draft",
      programDays: [
        committed,
        ProgramDay(id: "d3", title: "Lower A"),
        ProgramDay(id: "d4", title: "Upper B"),
        suggested,
        ProgramDay(id: "d5", title: "Recovery walk", suggested: true),
      ],
    );

    test("committed and suggested days are countable separately", () {
      final c = program.programDays.where((d) => !d.suggested).length;
      final s = program.programDays.where((d) => d.suggested).length;
      expect(c, 3);
      expect(s, 2);
      // The spec's table: 3 committed + up to 2 suggested = 5 active days,
      // leaving two rest days.
      expect(c + s, 5);
    });

    test("the program name reflects the commitment, not the ceiling", () {
      // "(3) per week" is what the client agreed to. Suggested days are a
      // ceiling they may never use, so naming it (5) would overstate it.
      expect(program.name, contains("(3)"));
    });

    test("the generator's reasoning survives a copyWith", () {
      const withNotes = SavedProgram(
        id: "p2",
        name: "x",
        programNote: "Days per week couldn't cover every group twice.",
        suggestedNote: "One fewer suggested day: the client is a beginner.",
      );
      final approved = withNotes.copyWith(status: "active");
      // Approving a draft must not strip the explanation of how it was built
      // — that reasoning is the record of why this program looks like this.
      expect(approved.programNote, withNotes.programNote);
      expect(approved.suggestedNote, withNotes.suggestedNote);
      expect(approved.status, "active");
    });

    test("notes are absent on an ordinary coach-built program", () {
      const coachBuilt = SavedProgram(id: "p3", name: "Coach plan");
      expect(coachBuilt.programNote, isNull);
      expect(coachBuilt.suggestedNote, isNull);
    });
  });

  group("the split cycle turns on committed days alone", () {
    const days = [
      ProgramDay(id: "c1", title: "Upper"),
      ProgramDay(id: "c2", title: "Lower"),
      ProgramDay(id: "s1", title: "Recovery walk", suggested: true),
    ];

    ClientRecord recordWith(List<String> dayIdsInOrder) => ClientRecord(
          id: "client-1",
          workoutLogs: [
            for (var i = 0; i < dayIdsInOrder.length; i++)
              WorkoutLogEntry(
                id: "log-$i",
                date: "2026-10-0${i + 1}",
                loggedAt: "2026-10-0${i + 1}T09:00",
                programId: "p1",
                programName: "Plan",
                dayId: dayIdsInOrder[i],
                dayTitle: dayIdsInOrder[i],
              ),
          ],
        );

    test("finishing every committed day resets the cycle", () {
      // The regression this guards: with suggested days in the list, a client
      // who does everything they committed to would never close a cycle, and
      // their ticks would pile up forever for skipping an optional walk.
      expect(getCurrentCycleCompletedDays(recordWith(["c1", "c2"]), days), isEmpty);
    });

    test("a half-finished cycle still reports what's done", () {
      expect(getCurrentCycleCompletedDays(recordWith(["c1"]), days), {"c1"});
    });

    test("a suggested day is not what's holding the cycle open", () {
      // Logging the optional day as well changes nothing: the cycle already
      // closed on the committed pair, and the walk starts the next one.
      expect(getCurrentCycleCompletedDays(recordWith(["c1", "c2", "s1"]), days), {"s1"});
    });

    test("a suggested day alone doesn't close a cycle", () {
      expect(getCurrentCycleCompletedDays(recordWith(["s1"]), days), {"s1"});
    });

    test("a program with no suggested days behaves exactly as before", () {
      const plain = [
        ProgramDay(id: "c1", title: "Upper"),
        ProgramDay(id: "c2", title: "Lower"),
      ];
      expect(getCurrentCycleCompletedDays(recordWith(["c1"]), plain), {"c1"});
      expect(getCurrentCycleCompletedDays(recordWith(["c1", "c2"]), plain), isEmpty);
      expect(getCurrentCycleCompletedDays(recordWith(["c1", "c2", "c1"]), plain), {"c1"});
    });
  });
}

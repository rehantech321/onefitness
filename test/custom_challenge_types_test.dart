import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/challenge_utils.dart";
import "package:onefitness/data/models/booking.dart";
import "package:onefitness/data/models/challenge.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/habit_log_entry.dart";
import "package:onefitness/data/models/measurement.dart";

/// Gym-defined challenge types.
///
/// The whole design rests on one constraint: `calcChallengeScore` is a switch
/// over template keys, so a type that invented its own scoring would rank
/// everyone at zero. A custom type therefore adopts an existing scorer and
/// copies its key onto the challenge. These tests hold that arrangement
/// together — above all the one asserting that every basis a coach can pick
/// actually produces a score.
void main() {
  // A window safely in the past, so the habit scorer (which clamps its end to
  // today) sees the whole of it.
  const start = "2026-01-01";
  const end = "2026-01-02";

  Challenge custom(String basis, {String key = "custom-1", String emoji = "👟"}) => Challenge(
        id: "ch-1",
        template: key,
        name: "Step Count Challenge",
        metric: "Steps logged",
        startDate: start,
        endDate: end,
        scoringBasis: basis,
        emoji: emoji,
      );

  Booking checkedIn(String date) => Booking(
        id: "b-$date",
        clientId: "c1",
        trainerId: "t1",
        date: date,
        slot: 540,
        sessionType: "one-on-one",
        discipline: "personal-training",
        attendanceStatus: "checked-in",
      );

  Measurement measure(String date, {String? weight, String? bodyfat, String? chest}) =>
      Measurement(id: "m-$date", date: date, weight: weight, bodyfat: bodyfat, chest: chest);

  group("scoring basis routing", () {
    test("a built-in challenge still scores from its template", () {
      const builtIn = Challenge(
        id: "ch-b",
        template: "attendance",
        name: "Attendance Challenge",
        metric: "Sessions attended",
        startDate: start,
        endDate: end,
      );
      expect(scoringKey(builtIn), "attendance");
      expect(
        calcChallengeScore("c1", builtIn, null, [checkedIn(start), checkedIn(end)]),
        2,
      );
    });

    test("a custom type scores from its basis, not its own key", () {
      final c = custom("attendance");
      expect(scoringKey(c), "attendance");
      expect(calcChallengeScore("c1", c, null, [checkedIn(start), checkedIn(end)]), 2);
    });

    test("without a basis, an unknown template scores nothing — the trap this avoids", () {
      const orphan = Challenge(
        id: "ch-o",
        template: "custom-1",
        name: "Step Count Challenge",
        metric: "Steps logged",
        startDate: start,
        endDate: end,
      );
      expect(calcChallengeScore("c1", orphan, null, [checkedIn(start), checkedIn(end)]), 0);
    });
  });

  /// The guard that keeps `kScoringBases` and `calcChallengeScore` in step.
  /// Each case feeds in data that must produce a non-zero score, so a basis
  /// added to the picker without a matching branch fails here rather than
  /// shipping a leaderboard stuck at zero.
  group("every offered basis produces a score", () {
    final fixtures = <String, (ClientRecord?, List<Booking>)>{
      "attendance": (null, [checkedIn(start), checkedIn(end)]),
      "weight-loss": (
        ClientRecord(
          id: "c1",
          measurements: [measure(start, weight: "200"), measure(end, weight: "190")],
        ),
        const <Booking>[],
      ),
      "body-fat": (
        ClientRecord(
          id: "c1",
          measurements: [measure(start, bodyfat: "30"), measure(end, bodyfat: "25")],
        ),
        const <Booking>[],
      ),
      "inches-lost": (
        ClientRecord(
          id: "c1",
          measurements: [measure(start, chest: "40"), measure(end, chest: "38")],
        ),
        const <Booking>[],
      ),
      "30-day": (
        const ClientRecord(
          id: "c1",
          habits: ["water"],
          habitLogByDate: {
            start: HabitLogEntry(checked: {"water": true}),
            end: HabitLogEntry(checked: {"water": true}),
          },
        ),
        const <Booking>[],
      ),
      "fat-loss": (
        const ClientRecord(
          id: "c1",
          challengeProgress: {
            "ch-1": [ChallengeProgressEntry(value: 12, loggedAt: start)],
          },
        ),
        const <Booking>[],
      ),
    };

    for (final basis in kScoringBases) {
      test("${basis.key} (${basis.label})", () {
        final fixture = fixtures[basis.key];
        expect(
          fixture,
          isNotNull,
          reason: "No fixture for basis '${basis.key}'. A basis was added to kScoringBases "
              "without proving it scores — add one here.",
        );
        final (record, bookings) = fixture!;
        final score = calcChallengeScore("c1", custom(basis.key), record, bookings);
        expect(
          score,
          greaterThan(0),
          reason: "Basis '${basis.key}' scored 0 on data that should rank. "
              "calcChallengeScore has no branch for it, so every participant would "
              "sit at the bottom of the leaderboard forever.",
        );
      });
    }

    test("every basis key is one calcChallengeScore can reach", () {
      // kScoringBases deliberately reuses built-in template keys so no second
      // scorer has to exist. If one stops being a template key, the reuse has
      // been broken even if a branch happens to survive.
      for (final b in kScoringBases) {
        expect(
          kChallengeTemplates.containsKey(b.key),
          isTrue,
          reason: "'${b.key}' is not a built-in template key, so it has no scorer to borrow.",
        );
      }
    });
  });

  group("score presentation follows the basis", () {
    test("a percentage basis still reads as a percentage on a custom type", () {
      expect(scoreIsPercent(custom("body-fat")), isTrue);
      expect(scoreIsPercent(custom("30-day")), isTrue);
      expect(scoreIsPercent(custom("attendance")), isFalse);
    });

    test("a client-logged basis offers clients the log, whatever the type is called", () {
      // The bug this prevents: checking `template` would hide the entry field
      // on a custom type, leaving clients no way to put a number on the board.
      expect(needsClientLoggedScore(custom("fat-loss")), isTrue);
      expect(needsClientLoggedScore(custom("attendance")), isFalse);
    });
  });

  group("challengeDisplay", () {
    const stepType = ChallengeTemplate(
      key: "custom-1",
      emoji: "👟",
      label: "Step Count Challenge",
      metric: "Steps logged",
      description: "Walk the most.",
      basis: "attendance",
    );

    test("a built-in challenge reads from its built-in template", () {
      const builtIn = Challenge(
        id: "ch-b",
        template: "attendance",
        name: "January Attendance",
        metric: "Sessions attended",
        startDate: start,
        endDate: end,
      );
      final d = challengeDisplay(builtIn, const []);
      expect(d.typeLabel, "Attendance Challenge");
      expect(d.emoji, kChallengeTemplates["attendance"]!.emoji);
    });

    test("a custom challenge names its type", () {
      final d = challengeDisplay(custom("attendance"), const [stepType]);
      expect(d.typeLabel, "Step Count Challenge");
      expect(d.emoji, "👟");
    });

    test("still renders after its type is deleted", () {
      // Deleting a type must not reach back into challenges already run, so
      // the emoji comes off the challenge's own row.
      final d = challengeDisplay(custom("attendance"), const []);
      expect(d.emoji, "👟");
      expect(d.typeLabel, "Custom challenge");
      // And it must still rank.
      expect(calcChallengeScore("c1", custom("attendance"), null, [checkedIn(start)]), 1);
    });

    test("a custom type that reuses a built-in key is not mistaken for the built-in", () {
      // Keys are prefixed "custom-" to make this impossible, but the display
      // rule leans on scoringBasis rather than on the prefix.
      final clash = custom("attendance", key: "attendance", emoji: "🎯");
      final d = challengeDisplay(clash, const []);
      expect(d.emoji, "🎯");
      expect(d.typeLabel, isNot("Attendance Challenge"));
    });
  });

  group("who sees and manages a type", () {
    const gymWide = ChallengeTemplate(
      key: "custom-gym",
      emoji: "🏆",
      label: "Gym-wide",
      metric: "",
      description: "",
      basis: "attendance",
    );
    const mine = ChallengeTemplate(
      key: "custom-mine",
      emoji: "🏆",
      label: "Coach A's",
      metric: "",
      description: "",
      basis: "attendance",
      trainerId: "coach-a",
    );
    const theirs = ChallengeTemplate(
      key: "custom-theirs",
      emoji: "🏆",
      label: "Coach B's",
      metric: "",
      description: "",
      basis: "attendance",
      trainerId: "coach-b",
    );
    const all = [gymWide, mine, theirs];

    test("the owner sees every type", () {
      expect(visibleChallengeTypes(all, "owner").length, 3);
    });

    test("a coach sees gym-wide types and their own, not another coach's", () {
      final seen = visibleChallengeTypes(all, "coach-a").map((t) => t.key).toList();
      expect(seen, containsAll(["custom-gym", "custom-mine"]));
      expect(seen, isNot(contains("custom-theirs")));
    });

    test("the owner can remove any type", () {
      expect(canManageChallengeType(theirs, "owner"), isTrue);
      expect(canManageChallengeType(gymWide, "owner"), isTrue);
    });

    test("a coach can remove only their own — matching the table's RLS", () {
      expect(canManageChallengeType(mine, "coach-a"), isTrue);
      expect(canManageChallengeType(theirs, "coach-a"), isFalse);
      // A gym-wide type belongs to the owner, so a coach can't remove it out
      // from under everyone else.
      expect(canManageChallengeType(gymWide, "coach-a"), isFalse);
    });

    test("a signed-out session manages nothing", () {
      expect(canManageChallengeType(gymWide, null), isFalse);
      expect(canManageChallengeType(mine, null), isFalse);
    });
  });
}

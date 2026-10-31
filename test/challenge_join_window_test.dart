import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/challenge_utils.dart";
import "package:onefitness/data/models/challenge.dart";

/// When a challenge can be joined.
///
/// Registration used to close on the start date. A gym's Weight Loss
/// Challenge ran 21 Oct to 11 Nov, so from the 22nd there was no Join button
/// anywhere — the challenge ran for three more weeks with an empty
/// leaderboard and no way for anyone to get onto it.
void main() {
  const challenge = Challenge(
    id: "ch-1",
    template: "weight-loss",
    name: "Weight Loss Challenge",
    metric: "Lbs lost",
    startDate: "2026-10-21",
    endDate: "2026-11-11",
  );

  test("registration opens six days before the start", () {
    expect(registrationOpensDate(challenge), "2026-10-15");
  });

  group("joining", () {
    test("is closed before registration opens", () {
      expect(canJoinChallenge(challenge, "2026-10-14"), isFalse);
    });

    test("opens on the registration date", () {
      expect(canJoinChallenge(challenge, "2026-10-15"), isTrue);
    });

    test("is open in the run-up and on the start date", () {
      expect(canJoinChallenge(challenge, "2026-10-18"), isTrue);
      expect(canJoinChallenge(challenge, "2026-10-21"), isTrue);
    });

    test("stays open after the challenge has started", () {
      // The regression. On 31 Oct — the day this was reported — the button
      // had been gone for ten days.
      expect(canJoinChallenge(challenge, "2026-10-22"), isTrue);
      expect(canJoinChallenge(challenge, "2026-10-31"), isTrue);
    });

    test("is open on the final day", () {
      expect(canJoinChallenge(challenge, "2026-11-11"), isTrue);
    });

    test("closes once the challenge has ended", () {
      // Mirrors join_challenge's own `end_date >= today` guard, so the button
      // and the database agree on when it's over.
      expect(canJoinChallenge(challenge, "2026-11-12"), isFalse);
      expect(canJoinChallenge(challenge, "2026-12-01"), isFalse);
    });

    test("a one-day challenge can still be joined on the day", () {
      const sameDay = Challenge(
        id: "ch-2",
        template: "attendance",
        name: "One-day",
        metric: "Sessions attended",
        startDate: "2026-11-01",
        endDate: "2026-11-01",
      );
      expect(canJoinChallenge(sameDay, "2026-11-01"), isTrue);
      expect(canJoinChallenge(sameDay, "2026-10-26"), isTrue);
      expect(canJoinChallenge(sameDay, "2026-11-02"), isFalse);
    });
  });

  group("ranking the people in it", () {
    test("orders by score, highest first", () {
      final ranked = _rank([("a", 2.0), ("b", 9.0), ("c", 5.0)]);
      expect(ranked.map((e) => e.$1), ["b", "c", "a"]);
      expect(ranked.map((e) => e.$2), [1, 2, 3]);
    });

    test("a tie shares a place, and the next one skips", () {
      // Two clients on 5 lbs are both 1st, and the next is 3rd — not 2nd.
      final ranked = _rank([("a", 5.0), ("b", 5.0), ("c", 1.0)]);
      expect(ranked.map((e) => e.$2), [1, 1, 3]);
    });

    test("everyone on zero is joint first", () {
      // What a brand-new challenge looks like: nobody has logged anything,
      // and nobody is ranked above anyone else for it.
      final ranked = _rank([("a", 0.0), ("b", 0.0), ("c", 0.0)]);
      expect(ranked.map((e) => e.$2), [1, 1, 1]);
    });
  });
}

/// The placement rule the leaderboard uses, in both the app and
/// `_shared/challengeScoring.ts`: sort by score, and only move the place
/// number when the score actually drops.
List<(String, int)> _rank(List<(String, double)> entries) {
  final sorted = [...entries]..sort((a, b) => b.$2.compareTo(a.$2));
  var place = 1;
  final out = <(String, int)>[];
  for (var i = 0; i < sorted.length; i++) {
    if (i > 0 && sorted[i].$2 < sorted[i - 1].$2) place = i + 1;
    out.add((sorted[i].$1, place));
  }
  return out;
}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/notifications/beep_sounds.dart";
import "package:onefitness/data/models/live_session.dart";

/// Beep Your Coach exists because a coach running a semi-private session in
/// a large gym cannot watch everyone. The rules that matter most are the
/// ones about what reaches the coach and in what order, so those are what
/// these pin.
void main() {
  Beep beep(
    String id,
    BeepKind kind, {
    String createdAt = "2026-10-10T18:00:00Z",
    String? acknowledgedAt,
    String? cancelledAt,
    String? exercise,
    String trainerId = "coach-1",
    String clientId = "client-1",
  }) =>
      Beep(
        id: id,
        sessionRunId: "run-1",
        clientId: clientId,
        trainerId: trainerId,
        kind: kind,
        createdAt: createdAt,
        exercise: exercise,
        acknowledgedAt: acknowledgedAt,
        cancelledAt: cancelledAt,
      );

  group("what each request means", () {
    test("Help and Spot wait for the coach; Done does not", () {
      expect(BeepKind.help.needsAcknowledgement, isTrue);
      expect(BeepKind.spot.needsAcknowledgement, isTrue);
      // Done is a banner that clears itself, so it is never queued.
      expect(BeepKind.done.needsAcknowledgement, isFalse);
    });

    test("only Spot is urgent", () {
      expect(BeepKind.spot.isUrgent, isTrue);
      expect(BeepKind.help.isUrgent, isFalse);
      expect(BeepKind.done.isUrgent, isFalse);
    });

    test("kinds survive the round trip through the database", () {
      for (final k in BeepKind.values) {
        expect(BeepKindX.fromKey(k.key), k);
      }
      expect(BeepKindX.fromKey("nonsense"), isNull);
    });
  });

  group("what is still outstanding for the coach", () {
    test("a fresh Help is open", () {
      expect(beep("a", BeepKind.help).isOpen, isTrue);
    });

    test("an acknowledged Help is not", () {
      expect(beep("a", BeepKind.help, acknowledgedAt: "2026-10-10T18:01:00Z").isOpen, isFalse);
    });

    test("a cancelled Help is not, even before acknowledgement", () {
      expect(beep("a", BeepKind.help, cancelledAt: "2026-10-10T18:00:30Z").isOpen, isFalse);
    });

    test("a cancelled Help is not, even AFTER acknowledgement", () {
      // The spec is explicit: cancelling clears it on the coach's side even
      // once they've acknowledged it.
      final b = beep("a", BeepKind.help,
          acknowledgedAt: "2026-10-10T18:01:00Z", cancelledAt: "2026-10-10T18:02:00Z");
      expect(b.isOpen, isFalse);
      expect(b.isCancelled, isTrue);
    });

    test("Done is never outstanding", () {
      expect(beep("a", BeepKind.done).isOpen, isFalse);
    });
  });

  group("the order the coach sees them in", () {
    test("oldest first when nothing is urgent", () {
      final list = [
        beep("new", BeepKind.help, createdAt: "2026-10-10T18:05:00Z"),
        beep("old", BeepKind.help, createdAt: "2026-10-10T18:01:00Z"),
      ]..sort(compareBeepPriority);
      expect(list.map((b) => b.id), ["old", "new"]);
    });

    test("a Spot jumps the queue however late it arrives", () {
      final list = [
        beep("help-old", BeepKind.help, createdAt: "2026-10-10T18:00:00Z"),
        beep("help-mid", BeepKind.help, createdAt: "2026-10-10T18:01:00Z"),
        beep("spot-newest", BeepKind.spot, createdAt: "2026-10-10T18:09:00Z"),
      ]..sort(compareBeepPriority);
      expect(list.first.id, "spot-newest");
    });

    test("two Spots keep their own order between them", () {
      final list = [
        beep("spot-new", BeepKind.spot, createdAt: "2026-10-10T18:05:00Z"),
        beep("spot-old", BeepKind.spot, createdAt: "2026-10-10T18:02:00Z"),
        beep("help", BeepKind.help, createdAt: "2026-10-10T18:00:00Z"),
      ]..sort(compareBeepPriority);
      expect(list.map((b) => b.id), ["spot-old", "spot-new", "help"]);
    });
  });

  group("what the client is told", () {
    test("waiting, until the coach answers", () {
      expect(beep("a", BeepKind.help).clientStatus, "Waiting for your coach…");
    });

    test("Help answered reads 'Coach is coming'", () {
      expect(
        beep("a", BeepKind.help, acknowledgedAt: "2026-10-10T18:01:00Z").clientStatus,
        "Coach is coming",
      );
    });

    test("Spot answered reads the same", () {
      expect(
        beep("a", BeepKind.spot, acknowledgedAt: "2026-10-10T18:01:00Z").clientStatus,
        "Coach is coming",
      );
    });

    test("Done reads 'Coach notified' and never waits", () {
      // Done is not a request, so it must not imply anyone is coming.
      expect(beep("a", BeepKind.done).clientStatus, "Coach notified");
    });

    test("a cancelled beep says nothing at all", () {
      expect(beep("a", BeepKind.help, cancelledAt: "2026-10-10T18:00:30Z").clientStatus, isNull);
    });
  });

  group("when beeping is possible at all", () {
    // Started just now: a session is live only until its own length runs
    // out, so a fixed past timestamp here would be an expired session.
    LiveSession run({String type = "semi-private", String? endedAt}) => LiveSession(
          id: "run-1",
          trainerId: "coach-1",
          date: "2026-10-10",
          slotMin: 1260,
          sessionType: type,
          startedAt: DateTime.now().toUtc().toIso8601String(),
          endedAt: endedAt,
        );

    test("a running semi-private session supports it", () {
      expect(run().supportsBeep, isTrue);
    });

    test("not once the coach has ended the session", () {
      expect(run(endedAt: "2026-10-10T19:00:00Z").supportsBeep, isFalse);
    });

    test("not once the session's own time has run out", () {
      final expired = LiveSession(
        id: "run-1",
        trainerId: "coach-1",
        date: "2026-10-10",
        slotMin: 1260,
        sessionType: "semi-private",
        startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 61)).toIso8601String(),
      );
      expect(expired.supportsBeep, isFalse);
    });

    test("not in a one-on-one — the coach is already standing there", () {
      expect(run(type: "one-on-one").supportsBeep, isFalse);
    });

    test("not in a large group", () {
      expect(run(type: "large-group").supportsBeep, isFalse);
    });
  });

  group("alert sounds", () {
    test("every request type offers at least five", () {
      // The spec asks for five options per alert type.
      for (final kind in BeepKind.values) {
        expect(soundsFor(kind).length, greaterThanOrEqualTo(5), reason: kind.key);
      }
    });

    test("no sound file is shared between two types", () {
      // Help, Spot and Done have to be distinguishable by ear alone.
      final all = [for (final k in BeepKind.values) ...soundsFor(k).map((s) => s.asset)];
      expect(all.toSet().length, all.length);
    });

    test("an unset choice falls back to that type's first option", () {
      for (final kind in BeepKind.values) {
        expect(resolveSound(kind, null).id, soundsFor(kind).first.id);
        expect(defaultSoundId(kind), soundsFor(kind).first.id);
      }
    });

    test("a saved id that no longer exists falls back rather than failing", () {
      // An owner's old choice must never leave a coach with silence.
      expect(resolveSound(BeepKind.spot, "deleted_sound").id, soundsFor(BeepKind.spot).first.id);
    });

    test("a saved choice is honoured", () {
      final third = soundsFor(BeepKind.help)[2];
      expect(resolveSound(BeepKind.help, third.id).id, third.id);
    });

    test("a sound id is never resolved across types", () {
      // Asking for a Help id while playing a Spot must not yield the Help
      // tone — the two mean very different things on the floor.
      final helpId = soundsFor(BeepKind.help).first.id;
      expect(resolveSound(BeepKind.spot, helpId).id, isNot(helpId));
    });
  });

  group("parsing a row from the database", () {
    test("a complete row", () {
      final b = Beep.fromJson({
        "id": "b1",
        "session_run_id": "r1",
        "client_id": "c1",
        "trainer_id": "t1",
        "kind": "spot",
        "exercise": "Bench Press",
        "created_at": "2026-10-10T18:00:00Z",
      });
      expect(b, isNotNull);
      expect(b!.kind, BeepKind.spot);
      expect(b.exercise, "Bench Press");
      expect(b.isOpen, isTrue);
    });

    test("a blank exercise becomes null, not an empty label", () {
      final b = Beep.fromJson({"id": "b1", "kind": "help", "exercise": "   "});
      expect(b!.exercise, isNull);
    });

    test("an unknown kind is dropped rather than guessed", () {
      expect(Beep.fromJson({"id": "b1", "kind": "shout"}), isNull);
    });

    test("a row with no id is dropped", () {
      expect(Beep.fromJson({"kind": "help"}), isNull);
    });
  });
}

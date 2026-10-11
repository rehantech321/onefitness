import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/booking.dart";
import "package:onefitness/data/models/live_session.dart";
import "package:onefitness/core/widgets/session_timer.dart";

/// A coach could start a 9pm session at 9:52 in the morning, which meant
/// logging sets against a session that hadn't happened. These pin when a
/// session may be started, and what the running clock shows.
void main() {
  const today = "2026-10-10";
  const ninePm = 21 * 60;

  /// The rule as the coach's dashboard applies it. Kept here in the same
  /// shape so the conditions can be tested without pumping the whole
  /// dashboard, which needs a signed-in coach and a loaded roster.
  bool tooEarly({
    required String viewDate,
    required String today,
    required int nowMin,
    required int slot,
    required bool someoneCheckedIn,
  }) {
    if (viewDate.compareTo(today) > 0) return true;
    return viewDate == today && nowMin < slot && !someoneCheckedIn;
  }

  Booking booking({String? attendanceStatus, String? clientStartedAt}) => Booking(
        id: "b1",
        clientId: "c1",
        trainerId: "t1",
        date: today,
        slot: ninePm,
        sessionType: "semi-private",
        discipline: "personal-training",
        attendanceStatus: attendanceStatus,
        clientStartedAt: clientStartedAt,
      );

  group("when a coach may start a session", () {
    test("not in the morning for a session that evening", () {
      // The reported bug, exactly: 9:52am, session at 9:00pm.
      expect(
        tooEarly(viewDate: today, today: today, nowMin: 9 * 60 + 52, slot: ninePm, someoneCheckedIn: false),
        isTrue,
      );
    });

    test("not a minute before it is due", () {
      expect(
        tooEarly(viewDate: today, today: today, nowMin: ninePm - 1, slot: ninePm, someoneCheckedIn: false),
        isTrue,
      );
    });

    test("yes, on the minute", () {
      expect(
        tooEarly(viewDate: today, today: today, nowMin: ninePm, slot: ninePm, someoneCheckedIn: false),
        isFalse,
      );
    });

    test("yes, once it is under way", () {
      expect(
        tooEarly(viewDate: today, today: today, nowMin: ninePm + 30, slot: ninePm, someoneCheckedIn: false),
        isFalse,
      );
    });

    test("never for a session on a future day", () {
      expect(
        tooEarly(viewDate: "2026-10-11", today: today, nowMin: 23 * 60, slot: ninePm, someoneCheckedIn: false),
        isTrue,
      );
    });

    test("a future day stays blocked even if someone checked in", () {
      // Guards against the early-arrival exception leaking across days.
      expect(
        tooEarly(viewDate: "2026-10-11", today: today, nowMin: 23 * 60, slot: ninePm, someoneCheckedIn: true),
        isTrue,
      );
    });
  });

  group("the early-arrival exception", () {
    // A client can start their own session early. If the coach were hard
    // blocked until the slot time, that client would be training with no
    // live session — and so no way to beep their coach.
    test("a client checking in early unlocks the coach's start", () {
      expect(
        tooEarly(viewDate: today, today: today, nowMin: 18 * 60, slot: ninePm, someoneCheckedIn: true),
        isFalse,
      );
    });

    test("without an early arrival it stays blocked at the same moment", () {
      expect(
        tooEarly(viewDate: today, today: today, nowMin: 18 * 60, slot: ninePm, someoneCheckedIn: false),
        isTrue,
      );
    });
  });

  group("the running clock", () {
    LiveSession runStarted(Duration ago, {int durationMin = 60}) => LiveSession(
          id: "run-1",
          trainerId: "coach-1",
          date: today,
          slotMin: ninePm,
          sessionType: "semi-private",
          durationMin: durationMin,
          startedAt: DateTime.now().toUtc().subtract(ago).toIso8601String(),
        );

    Future<String> shown(WidgetTester tester, LiveSession run) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SessionTimer(run: run))));
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      return texts.firstWhere((t) => t != null && RegExp(r"^\d+:\d{2}").hasMatch(t))!;
    }

    /// The clock is read a fraction of a second after the start time is
    /// built, so an exact match would be flaky by one second. Seconds-level
    /// tolerance still catches a clock counting the wrong way, from the
    /// wrong origin, or from the wrong duration.
    void expectAbout(String shownText, Duration expected) {
      final parts = shownText.split(":").map(int.parse).toList();
      final seconds = parts.length == 3
          ? parts[0] * 3600 + parts[1] * 60 + parts[2]
          : parts[0] * 60 + parts[1];
      expect(seconds, closeTo(expected.inSeconds, 2), reason: "showed $shownText");
    }

    testWidgets("counts DOWN from the session's length", (tester) async {
      // Twelve minutes in, forty-eight left of the hour.
      expectAbout(await shown(tester, runStarted(const Duration(minutes: 12))), const Duration(minutes: 48));
    });

    testWidgets("counts from when the session started, not from first build", (tester) async {
      // Backing out and returning rebuilds this widget; the clock must not
      // restart.
      expectAbout(await shown(tester, runStarted(const Duration(minutes: 12, seconds: 5))),
          const Duration(minutes: 47, seconds: 55));
    });

    testWidgets("a 30-minute session counts down from 30, not 60", (tester) async {
      expectAbout(await shown(tester, runStarted(const Duration(minutes: 5), durationMin: 30)),
          const Duration(minutes: 25));
    });

    testWidgets("a 90-minute session shows hours", (tester) async {
      final text = await shown(tester, runStarted(Duration.zero, durationMin: 90));
      expect(text.split(":").length, 3, reason: "should read h:mm:ss, got $text");
      expectAbout(text, const Duration(minutes: 90));
    });

    testWidgets("never goes negative once the time is up", (tester) async {
      expect(await shown(tester, runStarted(const Duration(minutes: 75))), "0:00");
    });

    testWidgets("an unparseable start time doesn't crash the session screen", (tester) async {
      const broken = LiveSession(
        id: "run-1",
        trainerId: "coach-1",
        date: today,
        slotMin: ninePm,
        sessionType: "semi-private",
        startedAt: "not a timestamp",
      );
      expect(await shown(tester, broken), "0:00");
    });
  });

  group("a session ends when its time runs out", () {
    LiveSession run(Duration ago, {int durationMin = 60, String? endedAt}) => LiveSession(
          id: "run-1",
          trainerId: "coach-1",
          date: today,
          slotMin: ninePm,
          sessionType: "semi-private",
          durationMin: durationMin,
          startedAt: DateTime.now().toUtc().subtract(ago).toIso8601String(),
          endedAt: endedAt,
        );

    test("still live part-way through", () {
      expect(run(const Duration(minutes: 30)).isLive, isTrue);
      expect(run(const Duration(minutes: 30)).supportsBeep, isTrue);
    });

    test("over once the hour is up, with no write needed", () {
      // The coach's phone may be locked or out of signal when the hour
      // ends; the clients in the session must still stop being able to beep.
      final finished = run(const Duration(minutes: 61));
      expect(finished.isLive, isFalse);
      expect(finished.supportsBeep, isFalse);
    });

    test("a session that ran out is flagged for closing off", () {
      expect(run(const Duration(minutes: 61)).hasRunOut, isTrue);
    });

    test("one already ended is not flagged again", () {
      // Otherwise the coach's screen would keep trying to end it.
      expect(run(const Duration(minutes: 61), endedAt: "2026-10-10T22:00:00Z").hasRunOut, isFalse);
    });

    test("one still running is not flagged", () {
      expect(run(const Duration(minutes: 10)).hasRunOut, isFalse);
    });

    test("a short session ends at its own length, not at an hour", () {
      expect(run(const Duration(minutes: 35), durationMin: 30).isLive, isFalse);
      expect(run(const Duration(minutes: 35), durationMin: 90).isLive, isTrue);
    });

    test("ending early still ends it", () {
      expect(run(const Duration(minutes: 5), endedAt: "2026-10-10T21:05:00Z").isLive, isFalse);
    });
  });

  group("what counts as a client arriving early", () {
    // The reported bug: a coach ticking someone present at 6:16pm unlocked
    // starting a 9pm session. Attendance and arrival are different facts.
    test("a coach marking someone checked-in does NOT count", () {
      final b = booking(attendanceStatus: "checked-in");
      expect(b.clientStartedEarly, isFalse);
    });

    test("the client starting their own session does count", () {
      final b = booking(
        attendanceStatus: "checked-in",
        clientStartedAt: "2026-10-10T18:00:00Z",
      );
      expect(b.clientStartedEarly, isTrue);
    });

    test("an untouched booking counts as neither", () {
      expect(booking().clientStartedEarly, isFalse);
    });

    test("the gate stays shut for a coach-marked check-in", () {
      // 6:16pm, session at 9pm, client ticked present by the coach.
      expect(
        tooEarly(
          viewDate: today,
          today: today,
          nowMin: 18 * 60 + 16,
          slot: ninePm,
          someoneCheckedIn: booking(attendanceStatus: "checked-in").clientStartedEarly,
        ),
        isTrue,
      );
    });

    test("and opens when the client started it themselves", () {
      expect(
        tooEarly(
          viewDate: today,
          today: today,
          nowMin: 18 * 60 + 16,
          slot: ninePm,
          someoneCheckedIn: booking(clientStartedAt: "2026-10-10T18:00:00Z").clientStartedEarly,
        ),
        isFalse,
      );
    });
  });

}

import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/booking.dart";
import "package:onefitness/features/trainer/schedule/session_move.dart";

/// The rules behind the Schedule screen's two drags.
///
/// Both moves are written to the database as insert-then-delete, so the
/// server still enforces capacity and coach conflicts (the booking trigger
/// fires BEFORE INSERT only). These checks exist so a coach is told *why* a
/// move won't work in a sentence they can act on, rather than being handed a
/// Postgres exception — and so a card that can't accept a drop doesn't light
/// up as though it can.
void main() {
  Booking booking({
    String id = "b1",
    String clientId = "c1",
    String trainerId = "t1",
    String date = "2026-11-10",
    int slot = 540, // 9:00
    String sessionType = "semi-private",
    String discipline = "personal-training",
    String status = "confirmed",
  }) => Booking(
    id: id,
    clientId: clientId,
    trainerId: trainerId,
    date: date,
    slot: slot,
    sessionType: sessionType,
    discipline: discipline,
    status: status,
  );

  /// The booking being dragged, plus whatever else is on the board.
  MoveCheck moveClient(
    Booking moving,
    List<Booking> others, {
    String toTrainerId = "t1",
    String toDate = "2026-11-10",
    int toSlot = 600, // 10:00
    String toSessionType = "semi-private",
    String toDiscipline = "personal-training",
    bool isOwner = true,
    int semiPrivateCap = 4,
  }) => checkClientMove(
    all: [moving, ...others],
    booking: moving,
    toTrainerId: toTrainerId,
    toDate: toDate,
    toSlot: toSlot,
    toSessionType: toSessionType,
    toDiscipline: toDiscipline,
    isOwner: isOwner,
    clientName: "Dana",
    semiPrivateCap: semiPrivateCap,
  );

  group("moving one client between sessions", () {
    test("dropped back on its own session, nothing happens", () {
      final b = booking();
      expect(moveClient(b, [], toSlot: 540), isA<MoveNoop>());
    });

    test("an empty slot on the same coach is fine", () {
      final result = moveClient(booking(), []);
      expect(result, isA<MoveAllowed>());
      expect((result as MoveAllowed).needsOverride, isFalse);
      expect(result.count, 0);
    });

    test("joining a session that has room is fine", () {
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c2", slot: 600),
      ]);
      expect(result, isA<MoveAllowed>());
      expect((result as MoveAllowed).count, 1);
    });

    test("a client already in the target session is refused by name", () {
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c1", slot: 600),
      ]);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("Dana"));
      expect(result.reason, contains("already in that session"));
    });

    test("a slot running a different session type for that coach is refused", () {
      // The coach can't run a one-on-one and a semi-private at 10:00.
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c2", slot: 600, sessionType: "one-on-one"),
      ]);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("different session"));
    });

    test("a client already booked with another coach at that time is refused", () {
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c1", trainerId: "t2", slot: 600),
      ]);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("already has a session"));
    });

    test("an overlapping — not identical — time still counts as a clash", () {
      // 9:30 with another coach overlaps a 10:00 start.
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c1", trainerId: "t2", slot: 570),
      ]);
      expect(result, isA<MoveRefused>());
    });

    test("a cancelled booking blocks nothing", () {
      // It holds no seat, so neither the client's diary nor the room is busy.
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c1", trainerId: "t2", slot: 600, status: "cancelled"),
      ]);
      expect(result, isA<MoveAllowed>());
    });

    test("a full session refuses a coach outright", () {
      // The database would refuse their insert, so offering the move and
      // then failing would be the worst of both.
      final full = [
        for (var i = 0; i < 2; i++) booking(id: "f$i", clientId: "x$i", slot: 600),
      ];
      final result = moveClient(booking(), full, isOwner: false, semiPrivateCap: 2);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("only the owner"));
    });

    test("a full session asks the owner to confirm, and says by how much", () {
      final full = [
        for (var i = 0; i < 2; i++) booking(id: "f$i", clientId: "x$i", slot: 600),
      ];
      final result = moveClient(booking(), full, isOwner: true, semiPrivateCap: 2);
      expect(result, isA<MoveAllowed>());
      final allowed = result as MoveAllowed;
      expect(allowed.needsOverride, isTrue);
      expect(allowed.count, 2);
      expect(allowed.cap, 2);
      expect(allowed.overBy, 1);
    });

    test("a one-on-one takes one client whatever the semi-private limit is", () {
      final result = moveClient(
        booking(),
        [booking(id: "b2", clientId: "c2", slot: 600, sessionType: "one-on-one")],
        toSessionType: "one-on-one",
        isOwner: false,
        semiPrivateCap: 8,
      );
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("limit of 1"));
    });

    test("moving to another coach's session on the same day is fine", () {
      final result = moveClient(booking(), [
        booking(id: "b2", clientId: "c2", trainerId: "t2", slot: 600),
      ], toTrainerId: "t2");
      expect(result, isA<MoveAllowed>());
    });
  });

  group("moving a whole session to another date", () {
    MoveCheck moveSession(
      List<Booking> group,
      List<Booking> others, {
      String toDate = "2026-11-12",
      String today = "2026-11-09",
      bool isOwner = true,
      int semiPrivateCap = 4,
    }) => checkSessionMove(
      all: [...group, ...others],
      group: group,
      toDate: toDate,
      today: today,
      isOwner: isOwner,
      semiPrivateCap: semiPrivateCap,
    );

    final pair = [
      booking(id: "b1", clientId: "c1"),
      booking(id: "b2", clientId: "c2"),
    ];

    test("dropped on the day it already sits on, nothing happens", () {
      expect(moveSession(pair, [], toDate: "2026-11-10"), isA<MoveNoop>());
    });

    test("a free day takes the whole session", () {
      final result = moveSession(pair, []);
      expect(result, isA<MoveAllowed>());
      expect((result as MoveAllowed).needsOverride, isFalse);
    });

    test("the past is refused", () {
      final result = moveSession(pair, [], toDate: "2026-11-08");
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("into the past"));
    });

    test("today is not the past", () {
      expect(moveSession(pair, [], toDate: "2026-11-09"), isA<MoveAllowed>());
    });

    test("a coach already running something else then is refused", () {
      final result = moveSession(pair, [
        booking(id: "o1", clientId: "c9", date: "2026-11-12", sessionType: "one-on-one"),
      ]);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("different session"));
    });

    test("a client in the session who is busy that day is refused", () {
      final result = moveSession(pair, [
        booking(id: "o1", clientId: "c2", trainerId: "t2", date: "2026-11-12"),
      ]);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("already booked"));
    });

    test("the whole group counts against the target's limit, not one seat", () {
      // Two already there plus the two moving is four — one over a cap of 3.
      final result = moveSession(pair, [
        booking(id: "o1", clientId: "c8", date: "2026-11-12"),
        booking(id: "o2", clientId: "c9", date: "2026-11-12"),
      ], isOwner: false, semiPrivateCap: 3);
      expect(result, isA<MoveRefused>());
      expect((result as MoveRefused).reason, contains("would make it 4"));
    });

    test("the owner can confirm past the limit, and is told the real total", () {
      final result = moveSession(pair, [
        booking(id: "o1", clientId: "c8", date: "2026-11-12"),
        booking(id: "o2", clientId: "c9", date: "2026-11-12"),
      ], isOwner: true, semiPrivateCap: 3);
      expect(result, isA<MoveAllowed>());
      final allowed = result as MoveAllowed;
      expect(allowed.needsOverride, isTrue);
      expect(allowed.count, 2);
      expect(allowed.overBy, 1);
    });

    test("exactly filling the target is allowed without a confirmation", () {
      final result = moveSession(pair, [
        booking(id: "o1", clientId: "c8", date: "2026-11-12"),
        booking(id: "o2", clientId: "c9", date: "2026-11-12"),
      ], isOwner: false, semiPrivateCap: 4);
      expect(result, isA<MoveAllowed>());
      expect((result as MoveAllowed).needsOverride, isFalse);
    });

    test("an empty group is refused rather than silently doing nothing", () {
      expect(moveSession([], []), isA<MoveRefused>());
    });
  });
}

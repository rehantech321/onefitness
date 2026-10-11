/// A session a coach has actually started — one row in `session_runs`.
///
/// Before this existed, "Start Session" was local state inside the coach's
/// own screen, so nothing outside that device knew a session was running.
/// Beep Your Coach turns on only while a coach has a session live and only
/// for the clients booked into it, so both sides need to see the same fact.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.trainerId,
    required this.date,
    required this.slotMin,
    required this.sessionType,
    required this.startedAt,
    this.durationMin = 60,
    this.location,
    this.endedAt,
  });

  final String id;
  final String trainerId;
  final String date; // ISO yyyy-MM-dd
  final int slotMin;
  final String sessionType;
  final String startedAt;

  /// How long this session runs for, copied from the booking when it
  /// started. Both screens work the end out from started_at + this, so they
  /// agree without either having to write first — and a session whose coach
  /// has closed the app still finishes on time for the clients in it.
  final int durationMin;
  final String? location;
  final String? endedAt;

  DateTime? get startedAtTime => DateTime.tryParse(startedAt)?.toUtc();

  /// When this session is due to finish.
  DateTime? get endsAt => startedAtTime?.add(Duration(minutes: durationMin));

  /// Time left, floored at zero. Null when the start time can't be read.
  Duration? get remaining {
    final ends = endsAt;
    if (ends == null) return null;
    final left = ends.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// A session is over when the coach ends it, or when its own time runs
  /// out — whichever comes first.
  ///
  /// Deriving the second case rather than waiting for a write matters: the
  /// coach's phone might be locked, out of signal, or closed when the hour
  /// is up, and the clients in the session must not be left able to beep a
  /// coach whose session finished twenty minutes ago.
  bool get isLive {
    if (endedAt != null) return false;
    final left = remaining;
    if (left == null) return true; // unparseable start: trust ended_at
    return left > Duration.zero;
  }

  /// Ran its full length without anyone ending it — what the coach's screen
  /// acts on to close the session off properly.
  bool get hasRunOut => endedAt == null && remaining == Duration.zero;

  /// Beep Your Coach is a semi-private feature: in a one-on-one the coach is
  /// already standing with the client, and in a large group a beep button
  /// would be a stampede.
  bool get supportsBeep => isLive && sessionType == "semi-private";

  static LiveSession? fromJson(Map<String, dynamic> j) {
    final id = j["id"]?.toString();
    final trainerId = j["trainer_id"]?.toString();
    if (id == null || trainerId == null) return null;
    return LiveSession(
      id: id,
      trainerId: trainerId,
      date: j["date"]?.toString() ?? "",
      slotMin: (j["slot_min"] as num?)?.toInt() ?? 0,
      sessionType: j["session_type"]?.toString() ?? "semi-private",
      location: j["location"]?.toString(),
      startedAt: j["started_at"]?.toString() ?? "",
      durationMin: (j["duration_min"] as num?)?.toInt() ?? 60,
      endedAt: j["ended_at"]?.toString(),
    );
  }
}

/// What a client is asking the coach for.
enum BeepKind { help, spot, done }

extension BeepKindX on BeepKind {
  String get key => switch (this) {
        BeepKind.help => "help",
        BeepKind.spot => "spot",
        BeepKind.done => "done",
      };

  String get label => switch (this) {
        BeepKind.help => "Help",
        BeepKind.spot => "Spot",
        BeepKind.done => "Done",
      };

  /// What the coach sees. Help and Spot are a full pop-up they must
  /// acknowledge; Done is a banner that clears itself, so it never covers
  /// the logging screen mid-set.
  bool get needsAcknowledgement => this != BeepKind.done;

  /// A spot request means someone is under a loaded bar. It jumps the queue,
  /// ignores the cooldown, and keeps re-buzzing until the coach answers.
  bool get isUrgent => this == BeepKind.spot;

  static BeepKind? fromKey(String? key) => switch (key) {
        "help" => BeepKind.help,
        "spot" => BeepKind.spot,
        "done" => BeepKind.done,
        _ => null,
      };
}

/// One client request raised during a live session — a row in `beeps`.
class Beep {
  const Beep({
    required this.id,
    required this.sessionRunId,
    required this.clientId,
    required this.trainerId,
    required this.kind,
    required this.createdAt,
    this.exercise,
    this.acknowledgedAt,
    this.cancelledAt,
  });

  final String id;
  final String sessionRunId;
  final String clientId;
  final String trainerId;
  final BeepKind kind;
  final String createdAt;

  /// Where the client was standing when they beeped, taken from their own
  /// session view. Null when they haven't opened their program — the coach
  /// then just sees the name and the request.
  final String? exercise;

  final String? acknowledgedAt;
  final String? cancelledAt;

  bool get isCancelled => cancelledAt != null;
  bool get isAcknowledged => acknowledgedAt != null;

  /// Still wants something from the coach. Done is never "open": it is
  /// information, not a request, so it is never queued for acknowledgement.
  bool get isOpen => !isCancelled && !isAcknowledged && kind.needsAcknowledgement;

  /// What the client is told once the coach has answered. A cancelled beep
  /// says nothing at all — it's gone from both sides.
  String? get clientStatus {
    if (isCancelled) return null;
    if (kind == BeepKind.done) return "Coach notified";
    return isAcknowledged ? "Coach is coming" : "Waiting for your coach…";
  }

  DateTime? get createdAtTime => DateTime.tryParse(createdAt)?.toLocal();

  Beep copyWith({String? acknowledgedAt, String? cancelledAt}) => Beep(
        id: id,
        sessionRunId: sessionRunId,
        clientId: clientId,
        trainerId: trainerId,
        kind: kind,
        createdAt: createdAt,
        exercise: exercise,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
      );

  static Beep? fromJson(Map<String, dynamic> j) {
    final id = j["id"]?.toString();
    final kind = BeepKindX.fromKey(j["kind"]?.toString());
    if (id == null || kind == null) return null;
    return Beep(
      id: id,
      sessionRunId: j["session_run_id"]?.toString() ?? "",
      clientId: j["client_id"]?.toString() ?? "",
      trainerId: j["trainer_id"]?.toString() ?? "",
      kind: kind,
      exercise: (j["exercise"] as String?)?.trim().isEmpty ?? true
          ? null
          : j["exercise"] as String?,
      createdAt: j["created_at"]?.toString() ?? "",
      acknowledgedAt: j["acknowledged_at"]?.toString(),
      cancelledAt: j["cancelled_at"]?.toString(),
    );
  }
}

/// How the coach's outstanding alerts are ordered: oldest first, except a
/// Spot always comes to the top however recently it arrived.
int compareBeepPriority(Beep a, Beep b) {
  if (a.kind.isUrgent != b.kind.isUrgent) return a.kind.isUrgent ? -1 : 1;
  return a.createdAt.compareTo(b.createdAt);
}

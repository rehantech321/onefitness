/// Mirrors one entry in client.comms (Comms.jsx) — a logged message, not a
/// live chat bubble; the whole feature is a timestamped communication log.
class CommMessage {
  const CommMessage({
    required this.id,
    required this.who, // "client" | "trainer"
    required this.text,
    required this.at, // pre-formatted display timestamp
    this.trainerId,
    this.readByCoach = false,
    this.channel,
    this.createdAt,
  });

  final String id;
  final String who;
  final String text;
  final String at;
  final String? trainerId;
  final bool readByCoach;

  /// "email" | "inapp" | "both" — how this message was also sent outside
  /// the app when it was composed. Null for messages logged before this
  /// was tracked, or from the original web app.
  final String? channel;

  /// The row's real `messages.created_at`, for messages stored in the
  /// `messages` table. Null for legacy entries that still live in
  /// `client_records.data->'comms'`, whose time is recovered from [id].
  final DateTime? createdAt;

  /// Real chronological timestamp for day-grouping/sort order in the chat
  /// UI. [id] is always a microsecond-epoch stamp for a message this app
  /// created (see chat_screen.dart/coach_chat_screen.dart's `send()`), so
  /// this recovers the exact original send time with no extra persisted
  /// field. Falls back to the epoch start (sorts first, never "now") for
  /// anything with a non-numeric id — e.g. legacy data from the web app's
  /// own `uid()` scheme.
  DateTime get sentAt {
    // A real timestamp always wins; table rows have UUID ids that carry no
    // time at all, so the old int.parse trick would sort them to the epoch.
    final stored = createdAt;
    if (stored != null) return stored;
    final micros = int.tryParse(id);
    return micros != null
        ? DateTime.fromMicrosecondsSinceEpoch(micros)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  CommMessage copyWith({bool? readByCoach}) => CommMessage(
        id: id,
        who: who,
        text: text,
        at: at,
        trainerId: trainerId,
        readByCoach: readByCoach ?? this.readByCoach,
        channel: channel,
        createdAt: createdAt,
      );
}

/// Mirrors one entry in `squad.chat` — Squad Chat's own N-party message
/// primitive, deliberately separate from `CommMessage` (the 1:1
/// client-coach communication log): `from` is always a member's client id,
/// never a coach, since no coach participates in Squad Chat.
class SquadChatMessage {
  const SquadChatMessage({
    required this.id,
    required this.from,
    required this.at,
    this.text,
    this.type = "text",
    this.shareKind,
    this.payload,
  });

  final String id;
  final String from; // member's client id
  final String at; // pre-formatted display timestamp

  final String? text;
  final String type; // "text" | "shared_progress"

  /// "measurements" | "exercises" | "photo" — only set when [type] is
  /// "shared_progress".
  final String? shareKind;

  /// The shared snapshot's data — shape depends on [shareKind]. Always a
  /// static point-in-time snapshot, never a live reference back to the
  /// sharer's current data.
  final Map<String, dynamic>? payload;

  /// Real chronological timestamp for day-grouping/sort order — [id] is
  /// always a microsecond-epoch stamp for a message this app created (see
  /// squad_chat_tab.dart's `send()`), same convention as
  /// CommMessage.sentAt. Falls back to the epoch start (sorts first, never
  /// "now") for anything with a non-numeric id.
  DateTime get sentAt {
    final micros = int.tryParse(id);
    return micros != null
        ? DateTime.fromMicrosecondsSinceEpoch(micros)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }
}

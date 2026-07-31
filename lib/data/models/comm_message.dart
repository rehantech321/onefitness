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
  });

  final String id;
  final String who;
  final String text;
  final String at;
  final String? trainerId;
  final bool readByCoach;

  CommMessage copyWith({bool? readByCoach}) => CommMessage(
        id: id,
        who: who,
        text: text,
        at: at,
        trainerId: trainerId,
        readByCoach: readByCoach ?? this.readByCoach,
      );
}

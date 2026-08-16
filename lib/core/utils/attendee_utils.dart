import "../../data/models/client_info.dart";
import "../../data/models/trainer.dart";

/// Mirrors chatHelpers.js `resolveAttendee` — a booking's `clientId` is
/// usually a real roster client, but a coach can also book *themselves*
/// into another coach's session ("Book session — Lead by example"), in
/// which case it's actually one of `trainers`. Falling back to "Unknown"
/// covers a client/trainer removed after the booking was made.
class ResolvedAttendee {
  const ResolvedAttendee({required this.name, this.photo, required this.isStaff});
  final String name;
  final String? photo;
  final bool isStaff;
}

ResolvedAttendee resolveAttendee(String id, List<ClientInfo> roster, List<Trainer> trainers) {
  final client = roster.where((x) => x.id == id);
  if (client.isNotEmpty) return ResolvedAttendee(name: client.first.name, photo: client.first.photo, isStaff: false);
  final trainer = trainers.where((x) => x.id == id);
  if (trainer.isNotEmpty) return ResolvedAttendee(name: trainer.first.name, photo: trainer.first.photo, isStaff: true);
  return const ResolvedAttendee(name: "Unknown", isStaff: false);
}

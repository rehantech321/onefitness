/// A minimal roster entry for other clients at the gym — used by Squad
/// member search. Not the full ClientInfo shape since we only need enough
/// to search/display/invite.
class RosterClient {
  const RosterClient({required this.id, required this.name, this.email, this.phone, this.photo});
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? photo;
}

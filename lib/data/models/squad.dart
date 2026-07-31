/// Mirrors one entry in `squad.memberMeta` — squadHelpers.js schema comment.
class SquadMemberMeta {
  const SquadMemberMeta({this.relationship = "", this.status = "active", this.paymentEnabled = false, this.minBalance = 0});

  final String relationship;
  final String status; // "active" | "inactive"
  final bool paymentEnabled;
  final num minBalance;

  SquadMemberMeta copyWith({String? relationship, bool? paymentEnabled, num? minBalance}) => SquadMemberMeta(
        relationship: relationship ?? this.relationship,
        status: status,
        paymentEnabled: paymentEnabled ?? this.paymentEnabled,
        minBalance: minBalance ?? this.minBalance,
      );
}

/// Mirrors one entry in `squad.pendingInvites`.
class SquadInvite {
  const SquadInvite({required this.clientId, required this.sentAt, this.status = "pending"});
  final String clientId;
  final String sentAt;
  final String status; // "pending" | "declined"
}

/// Mirrors one entry in `squad.activity`.
class SquadActivityEntry {
  const SquadActivityEntry({required this.id, required this.type, required this.at, this.actorName, this.description});
  final String id;
  final String type;
  final String at;
  final String? actorName;
  final String? description;
}

/// Mirrors `squad.membership` — a shared plan applied to the whole Squad.
class SquadMembership {
  const SquadMembership({
    required this.planName,
    required this.kind,
    required this.sessionsRemaining,
    required this.sessionsTotal,
    this.renewalDate,
  });
  final String planName;
  final String kind; // "membership" | "package"
  final int sessionsRemaining;
  final int sessionsTotal;
  final String? renewalDate;
}

const kDefaultSquadMax = 5;

/// Mirrors the Squad schema documented at the top of squadHelpers.js.
class Squad {
  const Squad({
    required this.id,
    this.name,
    required this.leadId,
    this.memberIds = const [],
    this.memberMeta = const {},
    this.maxSize = kDefaultSquadMax,
    this.membership,
    this.pendingInvites = const [],
    this.activity = const [],
  });

  final String id;
  final String? name;
  final String leadId;
  final List<String> memberIds;
  final Map<String, SquadMemberMeta> memberMeta;
  final int maxSize;
  final SquadMembership? membership;
  final List<SquadInvite> pendingInvites;
  final List<SquadActivityEntry> activity;

  String get displayName => name != null && name!.isNotEmpty ? name! : "Squad";

  int get pendingCount => pendingInvites.where((i) => i.status == "pending").length;

  bool canAddMember() => memberIds.length + pendingCount < maxSize;

  Squad copyWith({
    String? name,
    List<String>? memberIds,
    Map<String, SquadMemberMeta>? memberMeta,
    List<SquadInvite>? pendingInvites,
    List<SquadActivityEntry>? activity,
  }) =>
      Squad(
        id: id,
        name: name ?? this.name,
        leadId: leadId,
        memberIds: memberIds ?? this.memberIds,
        memberMeta: memberMeta ?? this.memberMeta,
        maxSize: maxSize,
        membership: membership,
        pendingInvites: pendingInvites ?? this.pendingInvites,
        activity: activity ?? this.activity,
      );

  Squad withActivity(String type, {String? actorName, String? description}) => copyWith(
        activity: [
          SquadActivityEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), type: type, at: _nowStamp(), actorName: actorName, description: description),
          ...activity,
        ],
      );
}

String _nowStamp() {
  final d = DateTime.now();
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? "AM" : "PM";
  return "${months[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ampm";
}

import "package:flutter_riverpod/flutter_riverpod.dart";
import "../mock/mock_data.dart";
import "../models/booking.dart";
import "../models/challenge.dart";
import "../models/client_info.dart";
import "../models/client_record.dart";
import "../models/earned_badge.dart";
import "../models/membership_plan.dart";
import "../models/points_ledger_entry.dart";
import "../models/roster_client.dart";
import "../models/squad.dart";
import "../models/trainer.dart";

/// Whether a client is currently signed in. UI-only phase: sign-in just
/// flips this on, standing in for the Supabase auth flow in App.jsx.
class ClientSignedIn extends Notifier<bool> {
  @override
  bool build() => false;

  void signIn() => state = true;
  void signOut() => state = false;
}

final clientSignedInProvider = NotifierProvider<ClientSignedIn, bool>(ClientSignedIn.new);

/// The signed-in client's roster/account record (App.jsx `info`).
class ClientInfoNotifier extends Notifier<ClientInfo> {
  @override
  ClientInfo build() => MockData.clientInfo;

  void update(ClientInfo Function(ClientInfo) updater) => state = updater(state);
}

final clientInfoProvider = NotifierProvider<ClientInfoNotifier, ClientInfo>(ClientInfoNotifier.new);

/// The signed-in client's day-to-day record (App.jsx `client`).
class ClientRecordNotifier extends Notifier<ClientRecord> {
  @override
  ClientRecord build() => MockData.clientRecord();

  void update(ClientRecord Function(ClientRecord) updater) => state = updater(state);
}

final clientRecordProvider = NotifierProvider<ClientRecordNotifier, ClientRecord>(ClientRecordNotifier.new);

/// All bookings for this client (App.jsx `bookings`, pre-filtered).
class ClientBookingsNotifier extends Notifier<List<Booking>> {
  @override
  List<Booking> build() => MockData.bookings();

  void addBooking(Booking b) => state = [...state, b];

  void cancelBooking(String id) => state = state.where((b) => b.id != id).toList();

  /// Reschedule: add the new booking and remove the original in one state
  /// update, so nothing observes the in-between state with neither/both.
  void reschedule(Booking newBooking, String originalId) =>
      state = [...state.where((b) => b.id != originalId), newBooking];
}

final clientBookingsProvider = NotifierProvider<ClientBookingsNotifier, List<Booking>>(ClientBookingsNotifier.new);

/// All trainers/coaches on staff (App.jsx `trainers`).
class TrainersNotifier extends Notifier<List<Trainer>> {
  @override
  List<Trainer> build() => MockData.trainers;

  void upsert(Trainer t) {
    final exists = state.any((x) => x.id == t.id);
    state = exists ? state.map((x) => x.id == t.id ? t : x).toList() : [...state, t];
  }

  void remove(String id) => state = state.where((t) => t.id != id).toList();
}

final trainersProvider = NotifierProvider<TrainersNotifier, List<Trainer>>(TrainersNotifier.new);

/// All membership/package/program plans the gym offers (App.jsx
/// `membershipPlans`) — coach-editable via Manage Memberships.
class MembershipPlansNotifier extends Notifier<List<MembershipPlan>> {
  @override
  List<MembershipPlan> build() => MockData.membershipPlans;

  void upsert(MembershipPlan p) {
    final exists = state.any((x) => x.id == p.id);
    state = exists ? state.map((x) => x.id == p.id ? p : x).toList() : [...state, p];
  }

  void archive(String id) => state = state.map((p) => p.id == id ? MembershipPlan(id: p.id, name: p.name, kind: p.kind, maxSessions: p.maxSessions, termMonths: p.termMonths, allowedTypes: p.allowedTypes, priceCents: p.priceCents, archived: true) : p).toList();

  void remove(String id) => state = state.where((p) => p.id != id).toList();

  MembershipPlan? byId(String? id) {
    if (id == null) return null;
    final matches = state.where((p) => p.id == id);
    return matches.isEmpty ? null : matches.first;
  }
}

final membershipPlansProvider = NotifierProvider<MembershipPlansNotifier, List<MembershipPlan>>(MembershipPlansNotifier.new);

/// Gym-wide challenges (App.jsx `challenges`).
class ChallengesNotifier extends Notifier<List<Challenge>> {
  @override
  List<Challenge> build() => MockData.challenges();

  void join(String challengeId, String clientId) => state = state
      .map((c) => c.id == challengeId && !c.participantIds.contains(clientId)
          ? c.copyWith(participantIds: [...c.participantIds, clientId])
          : c)
      .toList();

  void add(Challenge c) => state = [...state, c];

  void remove(String id) => state = state.where((c) => c.id != id).toList();
}

final challengesProvider = NotifierProvider<ChallengesNotifier, List<Challenge>>(ChallengesNotifier.new);

/// Other clients at the gym, for Squad member search (App.jsx `roster`).
final rosterProvider = Provider<List<RosterClient>>((ref) => MockData.roster);

/// All Squads (App.jsx `squads`) — starts empty; the signed-in client isn't
/// in one until they create/join it.
class SquadsNotifier extends Notifier<List<Squad>> {
  @override
  List<Squad> build() => [];

  Squad? squadFor(String clientId) {
    for (final s in state) {
      if (s.memberIds.contains(clientId)) return s;
    }
    return null;
  }

  void createSquad(Squad squad) => state = [...state, squad];

  void update(String squadId, Squad Function(Squad) updater) =>
      state = state.map((s) => s.id == squadId ? updater(s) : s).toList();

  void dissolve(String squadId) => state = state.where((s) => s.id != squadId).toList();
}

final squadsProvider = NotifierProvider<SquadsNotifier, List<Squad>>(SquadsNotifier.new);

/// Every client's earned Merit Badges (App.jsx `meritBadges`) — global list,
/// shared identically by the client's own Badge Gallery and the coach-side
/// MeritBadgesTab, same convention as squadsProvider.
class EarnedBadgesNotifier extends Notifier<List<EarnedBadge>> {
  @override
  List<EarnedBadge> build() => MockData.earnedBadges();

  void award(EarnedBadge badge) => state = [...state, badge];

  void revoke(String badgeId, {required String revokedAt, String? revokedByUserId}) =>
      state = state.map((b) => b.id == badgeId ? b.copyWith(revokedAt: revokedAt, revokedByUserId: revokedByUserId) : b).toList();
}

final earnedBadgesProvider = NotifierProvider<EarnedBadgesNotifier, List<EarnedBadge>>(EarnedBadgesNotifier.new);

/// Every client's points-ledger rows (App.jsx `pointsLedger`) — global
/// list, shared by the client's own Rewards screen and the coach-side
/// PointsTab.
class PointsLedgerNotifier extends Notifier<List<PointsLedgerEntry>> {
  @override
  List<PointsLedgerEntry> build() => MockData.pointsLedger();

  void add(PointsLedgerEntry entry) => state = [...state, entry];
}

final pointsLedgerProvider = NotifierProvider<PointsLedgerNotifier, List<PointsLedgerEntry>>(PointsLedgerNotifier.new);

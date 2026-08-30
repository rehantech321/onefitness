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
import "trainer_providers.dart";

/// Whether a client is currently signed in. UI-only phase: sign-in just
/// flips this on, standing in for the Supabase auth flow in App.jsx.
class ClientSignedIn extends Notifier<bool> {
  @override
  bool build() => false;

  void signIn() => state = true;
  void signOut() => state = false;
}

final clientSignedInProvider = NotifierProvider<ClientSignedIn, bool>(ClientSignedIn.new);

/// Whether ClientAuthScreen is currently showing ClientSignupScreen instead
/// of its sign-in form — read by the root shell to hide the Coach/Client
/// header toggle on the create-profile page (the user has already committed
/// to signing up as a client, so switching modes mid-form doesn't apply).
class ClientSigningUp extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final clientSigningUpProvider = NotifierProvider<ClientSigningUp, bool>(ClientSigningUp.new);

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

  void setAll(List<Booking> next) => state = next;
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

  void setAll(List<Trainer> next) => state = next;
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

  void remove(String id) => state = state.where((p) => p.id != id).toList();

  void setAll(List<MembershipPlan> next) => state = next;

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

  void update(String id, Challenge Function(Challenge) f) =>
      state = state.map((c) => c.id == id ? f(c) : c).toList();

  void setAll(List<Challenge> next) => state = next;
}

final challengesProvider = NotifierProvider<ChallengesNotifier, List<Challenge>>(ChallengesNotifier.new);

/// Other clients at the gym, for Squad member search (App.jsx `roster`).
/// Derived from trainerRosterProvider — the one place the full gym roster
/// actually gets loaded from Supabase (loadAndSeedCoreData seeds it
/// regardless of whether the signed-in session is a client or a coach) —
/// rather than the MockData placeholder this used to return unconditionally,
/// which made Squad search always come up empty against real clients.
final rosterProvider = Provider<List<RosterClient>>(
  (ref) => ref
      .watch(trainerRosterProvider)
      .map((c) => RosterClient(id: c.id, name: c.name, email: c.email, phone: c.phone, photo: c.photo))
      .toList(),
);

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

  /// Real deletion is coach/owner-only (squads_delete_staff_only) — kept for
  /// the coach-side "Remove Squad" action; the client-side "Dissolve Squad"
  /// button logs an activity entry instead (see SupabaseService.updateSquadRow).
  void dissolve(String squadId) => state = state.where((s) => s.id != squadId).toList();

  void setAll(List<Squad> next) => state = next;
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

  void setAll(List<EarnedBadge> next) => state = next;

  /// Swaps in a freshly-fetched slice for one client after a real
  /// award/revoke — the server, not local state, is the source of truth
  /// for what actually landed (id, earnedAt, and any points-sync side
  /// effect happen server-side).
  void replaceForClient(String clientId, List<EarnedBadge> fresh) =>
      state = [...state.where((b) => b.clientId != clientId), ...fresh];
}

final earnedBadgesProvider = NotifierProvider<EarnedBadgesNotifier, List<EarnedBadge>>(EarnedBadgesNotifier.new);

/// Every client's points-ledger rows (App.jsx `pointsLedger`) — global
/// list, shared by the client's own Rewards screen and the coach-side
/// PointsTab.
class PointsLedgerNotifier extends Notifier<List<PointsLedgerEntry>> {
  @override
  List<PointsLedgerEntry> build() => MockData.pointsLedger();

  void add(PointsLedgerEntry entry) => state = [...state, entry];

  void setAll(List<PointsLedgerEntry> next) => state = next;

  /// See EarnedBadgesNotifier.replaceForClient's doc comment — same reason.
  void replaceForClient(String clientId, List<PointsLedgerEntry> fresh) =>
      state = [...state.where((e) => e.clientId != clientId), ...fresh];
}

final pointsLedgerProvider = NotifierProvider<PointsLedgerNotifier, List<PointsLedgerEntry>>(PointsLedgerNotifier.new);

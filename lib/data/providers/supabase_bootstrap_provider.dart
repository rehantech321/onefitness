import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/supabase/supabase_service.dart";
import "../models/booking.dart";
import "../models/client_info.dart";
import "../models/client_record.dart";
import "../models/membership_plan.dart";
import "../models/trainer.dart";
import "client_providers.dart";
import "role_provider.dart";
import "trainer_providers.dart";

/// Runs once at app startup: restores the Supabase Auth session (if any),
/// then defers to [loadAndSeedCoreData] for the actual fetch+seed+restore
/// work — mirrors App.jsx's own "Step 1: core entities" bootstrap effect
/// (loadRoster/loadTrainers/loadBookings, then getSessionProfile-based
/// restore) as closely as possible while every other domain (badges,
/// points, memberships, programs, etc.) still runs on local mock state.
final supabaseBootstrapProvider = FutureProvider<void>((ref) async {
  await SupabaseService.ensureSession();
  await loadAndSeedCoreData(ref);
});

/// Fetches roster/trainers/bookings/membership-plans/client-records as
/// *whoever Supabase currently considers the caller* (anonymous or a
/// specific signed-in user — RLS scopes the actual rows returned either
/// way) and seeds every provider that depends on them, then restores
/// role/signed-in state from the current session's profile.
///
/// Called both by the startup bootstrap above (covers session-restore on
/// reload) AND right after every successful sign-in in
/// client_auth_screen.dart / trainer_auth_screen.dart — a fresh sign-in
/// happens *after* the anonymous bootstrap already ran (and would have
/// seen little to nothing under RLS), so without a second call here,
/// bookings/trainers would stay empty until the next reload.
///
/// Takes `dynamic` rather than `Ref` on purpose: Riverpod's `Ref` (used by
/// providers) and `WidgetRef` (used by widgets, e.g. a ConsumerState's
/// `ref`) are deliberately unrelated types with no common supertype, but
/// both expose the same `.read<T>(provider)` — this needs to be callable
/// from both a FutureProvider body and a sign-in screen's widget state.
Future<void> loadAndSeedCoreData(dynamic ref) async {
  final List<ClientInfo> roster;
  final List<Trainer> trainers;
  final List<Booking> bookings;
  final List<MembershipPlan> plans;
  try {
    roster = await SupabaseService.loadRoster();
    trainers = await SupabaseService.loadTrainers();
    bookings = await SupabaseService.loadBookings();
    plans = await SupabaseService.loadMembershipPlans();
  } catch (e, st) {
    // Anonymous caller blocked outright by RLS on one of these tables (vs.
    // just getting zero rows back), or the network's unavailable — leave
    // the mock seed data in place rather than blanking every screen out.
    // ignore: avoid_print
    print("[loadAndSeedCoreData] core fetch failed: $e\n$st");
    return;
  }

  // Seed both sides' independent copies of the same underlying data so
  // every already-built screen (which reads its own role-scoped provider)
  // keeps working unchanged.
  ref.read(trainerRosterProvider.notifier).setAll(roster);
  ref.read(trainersProvider.notifier).setAll(trainers);
  ref.read(allBookingsProvider.notifier).setAll(bookings);
  if (plans.isNotEmpty) ref.read(membershipPlansProvider.notifier).setAll(plans);

  final clientRecords = <String, ClientRecord>{};
  await Future.wait(roster.map((c) async {
    clientRecords[c.id] = await SupabaseService.loadClientRecord(c.id);
  }));
  ref.read(trainerClientRecordsProvider.notifier).setAll(clientRecords);

  // ── Restore who's signed in from the current Supabase Auth session ──
  final profile = await SupabaseService.getSessionProfile();
  if (profile == null) return;

  final role = profile["role"] as String?;
  final id = profile["id"] as String;

  if (role == "owner") {
    ref.read(roleProvider.notifier).set("trainer");
    ref.read(trainerAuthProvider.notifier).signIn("owner");
  } else if (role == "coach" && trainers.any((t) => t.id == id)) {
    ref.read(roleProvider.notifier).set("trainer");
    ref.read(trainerAuthProvider.notifier).signIn(id);
  } else if (role == "client") {
    final matches = roster.where((c) => c.id == id);
    if (matches.isEmpty) {
      // Session exists but their app-side row is gone — inert account.
      await SupabaseService.signOut();
      return;
    }
    ref.read(roleProvider.notifier).set("client");
    ref.read(clientInfoProvider.notifier).update((_) => matches.first);
    ref.read(clientRecordProvider.notifier).update((_) => clientRecords[id] ?? const ClientRecord(id: ""));
    ref.read(clientBookingsProvider.notifier).setAll(bookings.where((b) => b.clientId == id).toList());
    ref.read(clientSignedInProvider.notifier).signIn();
  }
}

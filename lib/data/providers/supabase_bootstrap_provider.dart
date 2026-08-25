import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../core/supabase/supabase_service.dart";
import "../models/blocked_time.dart";
import "../models/booking.dart";
import "../models/challenge.dart";
import "../models/charge.dart";
import "../models/client_info.dart";
import "../models/client_record.dart";
import "../models/coach_merit_badge.dart";
import "../models/coach_pr_event.dart";
import "../models/earned_badge.dart";
import "../models/exercise_def.dart";
import "../models/meal_def.dart";
import "../models/membership_plan.dart";
import "../models/points_ledger_entry.dart";
import "../models/product.dart";
import "../models/saved_program.dart";
import "../models/squad.dart";
import "../models/trainer.dart";
import "../models/waitlist_entry.dart";
import "../models/waiver_doc.dart";
import "client_providers.dart";
import "platform_settings_provider.dart";
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
  _subscribeRealtimeUpdates(ref);
});

/// Live-updates every already-open session (a coach editing exercises
/// while a client is mid-workout-builder, an owner changing a membership
/// plan while a client is on the Membership Hub, a policy change while
/// someone's mid-booking) — mirrors subscribeMembershipPlans/
/// subscribeExercises/subscribePlatformSettings in supabaseData.js. Set up
/// once here (this provider's own body only runs once per app session,
/// unlike loadAndSeedCoreData which reruns on every sign-in) rather than
/// per-screen, so it stays live regardless of which screen is on top.
/// Never explicitly unsubscribed — same as the source, which leaves these
/// live for the whole tab/session.
void _subscribeRealtimeUpdates(Ref ref) {
  SupabaseService.client
      .channel("membership_plans_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "membership_plans",
        callback: (payload) async {
          final plans = await SupabaseService.loadMembershipPlans();
          if (plans.isNotEmpty) ref.read(membershipPlansProvider.notifier).setAll(plans);
        },
      )
      .subscribe();

  SupabaseService.client
      .channel("exercises_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "exercises",
        callback: (payload) async {
          final exercises = await SupabaseService.loadExercises();
          if (exercises.isNotEmpty) ref.read(exerciseCatalogProvider.notifier).setAll(exercises);
        },
      )
      .subscribe();

  SupabaseService.client
      .channel("platform_settings_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "platform_settings",
        callback: (payload) async {
          final settings = await SupabaseService.loadPlatformSettings();
          if (settings != null) ref.read(platformSettingsProvider.notifier).update((_) => settings);
        },
      )
      .subscribe();
}

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
  final List<PointsLedgerEntry> pointsLedger;
  final List<EarnedBadge> badges;
  final List<BlockedTime> blockedTime;
  final List<Product> products;
  final List<WaiverDoc> waivers;
  final List<SavedProgram> programsLibrary;
  final List<MealDef> customMeals;
  final List<ExerciseDef> exercises;
  final List<Challenge> challenges;
  final List<Squad> squads;
  final List<Charge> charges;
  final List<WaitlistEntry> waitlist;
  final PlatformSettings? platformSettings;
  final List<String> packageCategories;
  final List<CoachMeritBadge> coachMeritBadges;
  final List<CoachPrEvent> coachPrEvents;
  try {
    // Firing all 16 requests before awaiting any of them (rather than one
    // `await` per line) starts them concurrently — each async call runs up
    // to its own first `await` immediately, so the actual network request
    // is already in flight by the time the next line runs. Grew from 4
    // sequential round trips (Part 1) to 16 across Parts 1-7; strictly
    // sequential awaits would make every fresh sign-in and app-startup
    // noticeably slower with each new domain wired up.
    final rosterF = SupabaseService.loadRoster();
    final trainersF = SupabaseService.loadTrainers();
    final bookingsF = SupabaseService.loadBookings();
    final plansF = SupabaseService.loadMembershipPlans();
    final pointsLedgerF = SupabaseService.loadPointsLedgerAll();
    final badgesF = SupabaseService.loadMeritBadgesAll();
    final blockedTimeF = SupabaseService.loadBlockedTime();
    final productsF = SupabaseService.loadProducts();
    final waiversF = SupabaseService.loadWaiverDocs();
    final programsLibraryF = SupabaseService.loadProgramsLibrary();
    final customMealsF = SupabaseService.loadCustomMeals();
    final exercisesF = SupabaseService.loadExercises();
    final challengesF = SupabaseService.loadChallenges();
    final squadsF = SupabaseService.loadSquads();
    final chargesF = SupabaseService.loadCharges();
    final waitlistF = SupabaseService.loadWaitlist();
    final platformSettingsF = SupabaseService.loadPlatformSettings();
    final packageCategoriesF = SupabaseService.loadPackageCategories();
    final coachMeritBadgesF = SupabaseService.loadCoachMeritBadges();
    final coachPrEventsF = SupabaseService.loadCoachPrEvents();

    roster = await rosterF;
    trainers = await trainersF;
    bookings = await bookingsF;
    plans = await plansF;
    pointsLedger = await pointsLedgerF;
    badges = await badgesF;
    blockedTime = await blockedTimeF;
    products = await productsF;
    waivers = await waiversF;
    programsLibrary = await programsLibraryF;
    customMeals = await customMealsF;
    exercises = await exercisesF;
    challenges = await challengesF;
    squads = await squadsF;
    charges = await chargesF;
    waitlist = await waitlistF;
    platformSettings = await platformSettingsF;
    packageCategories = await packageCategoriesF;
    coachMeritBadges = await coachMeritBadgesF;
    coachPrEvents = await coachPrEventsF;
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
  ref.read(pointsLedgerProvider.notifier).setAll(pointsLedger);
  ref.read(earnedBadgesProvider.notifier).setAll(badges);
  ref.read(blockedTimesProvider.notifier).setAll(blockedTime);
  ref.read(productsProvider.notifier).setAll(products);
  // Real, even if empty — but an empty real waiver list would silently drop
  // the one built-in default (used at client signup) that every mock-data
  // session had; keep that default until a gym actually defines their own.
  if (waivers.isNotEmpty) ref.read(waiversProvider.notifier).setAll(waivers);
  ref.read(programsLibraryProvider.notifier).setAll(programsLibrary);
  ref.read(customMealsProvider.notifier).setAll(customMeals);
  // Same reasoning as membership plans: don't blank out the curated mock
  // catalog (dozens of exercises) in favor of whatever handful a real gym
  // has actually entered so far, if none exist yet.
  if (exercises.isNotEmpty) ref.read(exerciseCatalogProvider.notifier).setAll(exercises);
  ref.read(challengesProvider.notifier).setAll(challenges);
  ref.read(squadsProvider.notifier).setAll(squads);
  ref.read(chargesProvider.notifier).setAll(charges);
  ref.read(waitlistProvider.notifier).setAll(waitlist);
  ref.read(packageCategoriesProvider.notifier).setAll(packageCategories);
  ref.read(coachMeritBadgesProvider.notifier).setAll(coachMeritBadges);
  ref.read(coachPrEventsProvider.notifier).setAll(coachPrEvents);
  // `platformSettings` is declared-then-assigned-in-a-try-block above, not
  // initialized at declaration — Dart doesn't carry a null-promotion for
  // that shape into a closure literal, so `(_) => platformSettings` below
  // would infer as `(dynamic) => PlatformSettings?` and throw at runtime
  // against `PlatformSettingsNotifier.update`'s non-nullable signature.
  // Re-binding to a plain initialized local fixes the promotion.
  final resolvedSettings = platformSettings;
  if (resolvedSettings != null) {
    ref.read(platformSettingsProvider.notifier).update((_) => resolvedSettings);
  }

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

/// Shared by squad_dashboard_screen.dart (client) and squad_tab.dart (coach)
/// — every Squad mutation in both follows this same compute-then-persist-
/// then-apply shape. Returns whether the write succeeded; local state is
/// only ever updated after the real write does, so a failed save can't
/// leave the UI showing something the database doesn't actually have.
Future<bool> mutateSquad(dynamic ref, Squad squad, Squad Function(Squad) f) async {
  final next = f(squad);
  try {
    await SupabaseService.updateSquadRow(
      squad.id,
      name: next.name,
      memberIds: next.memberIds,
      memberMeta: next.memberMeta,
      maxSize: next.maxSize,
      pendingInvites: next.pendingInvites,
      activity: next.activity,
    );
  } catch (e) {
    return false;
  }
  ref.read(squadsProvider.notifier).update(squad.id, (_) => next);
  return true;
}

import "dart:async";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../core/notifications/push_service.dart";
import "../../core/supabase/supabase_service.dart";
import "../models/booking.dart";
import "../models/challenge.dart";
import "../models/charge.dart";
import "../models/client_info.dart";
import "../models/client_record.dart";
import "../models/comm_message.dart";
import "../models/earned_badge.dart";
import "../models/exercise_def.dart";
import "../models/membership_plan.dart";
import "../models/points_ledger_entry.dart";
import "../models/squad.dart";
import "../models/trainer.dart";
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
  if (SupabaseService.currentUser == null) {
    // Nobody signed in: the only screens reachable are the sign-in and
    // sign-up pages, which need nothing but platform settings (the coach
    // signup's session types). Show them straight away and skip the full
    // load — every sign-in path runs loadAndSeedCoreData itself once the
    // credentials have been checked.
    unawaited(_loadSignedOutBasics(ref));
  } else {
    await loadAndSeedCoreData(ref);
  }
  _subscribeRealtimeUpdates(ref);
});

Future<void> _loadSignedOutBasics(Ref ref) async {
  try {
    final settings = await SupabaseService.loadPlatformSettings();
    if (settings != null) ref.read(platformSettingsProvider.notifier).update((_) => settings);
  } catch (e) {
    // The signup form falls back to its defaults; nothing to recover.
    // ignore: avoid_print
    print("[bootstrap] platform settings load failed: $e");
  }
}

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

  // Chat. Re-reads the affected thread rather than patching from the
  // payload, so a message that RLS hides (a blocked user's) never slips in
  // through the realtime path — the select policy is applied on the reread.
  SupabaseService.client
      .channel("messages_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "messages",
        callback: (payload) async {
          final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
          final clientId = row["client_id"] as String?;
          if (clientId == null) return;
          try {
            final thread = await SupabaseService.loadMessagesFor(clientId);
            // Newest first, matching how every chat screen reads `comms`.
            final ordered = thread.reversed.toList();
            ref.read(trainerClientRecordsProvider.notifier).update(
                  clientId,
                  (r) => r.copyWith(comms: ordered),
                );
            // The signed-in client's own copy is a separate provider.
            if (ref.read(clientInfoProvider).id == clientId) {
              ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(comms: ordered));
            }
          } catch (e) {
            // ignore: avoid_print
            print("[realtime messages] reload failed: $e");
          }
        },
      )
      .subscribe();

  // A client's saved programs, nutrition plan, intake answers and logs all
  // live on this row. Without this, a program the owner assigned only showed
  // up after the client fully restarted the app.
  SupabaseService.client
      .channel("client_records_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "client_records",
        callback: (payload) async {
          final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
          final profileId = row["profile_id"] as String?;
          if (profileId == null) return;
          try {
            // Re-read rather than trusting the payload, so RLS decides what
            // this user may actually see.
            final record = await SupabaseService.loadClientRecord(profileId);
            // Chat lives in its own table now; keep whatever the messages
            // channel has already put in place rather than blanking it.
            final existingComms =
                ref.read(trainerClientRecordsProvider)[profileId]?.comms ?? const [];
            final merged = record.copyWith(
              comms: record.comms.isEmpty ? existingComms : record.comms,
            );
            ref.read(trainerClientRecordsProvider.notifier).update(profileId, (_) => merged);
            if (ref.read(clientInfoProvider).id == profileId) {
              ref.read(clientRecordProvider.notifier).update((_) => merged);
            }
          } catch (e) {
            // ignore: avoid_print
            print("[realtime client_records] reload failed: $e");
          }
        },
      )
      .subscribe();

  // A client's membership, freeze and cancellation live on their `clients`
  // row. When staff cancel or freeze it, every open app — the client's own
  // and other staff — picks the change up here. Only delivers once `clients`
  // is in the supabase_realtime publication; until then the on-resume
  // refresh (refreshClientInfos) covers it.
  SupabaseService.client
      .channel("clients_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "clients",
        callback: (payload) async {
          final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
          final id = row["profile_id"] as String?;
          if (id == null) return;
          try {
            await refreshClientInfos(ref, onlyId: id);
          } catch (e) {
            // ignore: avoid_print
            print("[realtime clients] reload failed: $e");
          }
        },
      )
      .subscribe();

  // Merit Badges are otherwise fetched once, at bootstrap. The ONE Fitness
  // badge is awarded the instant a plan is bought (migration 18's trigger
  // on clients.membership_plan_id), so without this a client who just
  // bought a membership would see no badge until they next restarted the
  // app — indistinguishable, from their side, from it not being awarded at
  // all. The same applies to a coach awarding a PR badge while the client
  // is looking at their gallery.
  SupabaseService.client
      .channel("merit_badges_live")
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "merit_badges",
        callback: (payload) async {
          final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
          final clientId = row["client_id"] as String?;
          if (clientId == null) return;
          try {
            // Re-fetch rather than patch from the payload: RLS decides what
            // this viewer may see, and a revoke arrives as an update whose
            // old row is the one worth replacing.
            final fresh = await SupabaseService.loadMeritBadgesFor(clientId);
            ref.read(earnedBadgesProvider.notifier).replaceForClient(clientId, fresh);
          } catch (e) {
            // ignore: avoid_print
            print("[realtime merit_badges] reload failed: $e");
          }
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

/// Fetches what the app needs as *whoever Supabase currently considers the
/// caller* (RLS scopes the actual rows returned) and seeds every provider
/// that depends on it, then restores role/signed-in state from the current
/// session's profile.
///
/// Called by the startup bootstrap above when a session already exists, and
/// right after every successful sign-in in client_auth_screen.dart /
/// trainer_auth_screen.dart / the signup screens.
///
/// Two phases, so signing in doesn't wait on the whole database:
///  * Awaited — what the first screen and the role restore need: roster,
///    trainers, bookings, membership plans, waivers, platform settings,
///    client records and the session profile. The returned Future completes
///    once these are in, and the caller's shell opens.
///  * Background — everything else (points, badges, challenges, charges,
///    chat, libraries, catalogs …). Every request is fired at the start, so
///    these are already in flight; each one is applied as soon as it lands,
///    independently, so one slow or failing table doesn't hold up the rest.
///    Providers whose built-in default is sample data are emptied first, so
///    a real account never sees a fake charge or badge while they arrive.
///
/// Takes `dynamic` rather than `Ref` on purpose: Riverpod's `Ref` (used by
/// providers) and `WidgetRef` (used by widgets, e.g. a ConsumerState's
/// `ref`) are deliberately unrelated types with no common supertype, but
/// both expose the same `.read<T>(provider)` — this needs to be callable
/// from both a FutureProvider body and a sign-in screen's widget state.
/// The background phase must not touch `ref` itself: a sign-in screen is
/// disposed as soon as the shell replaces it, and its WidgetRef dies with
/// it. It works through notifiers read up front instead, which live on in
/// the ProviderScope.
Future<void> loadAndSeedCoreData(dynamic ref) async {
  final generation = ++_loadGeneration;

  // ── Fire every request now ──
  final rosterF = SupabaseService.loadRoster();
  final trainersF = SupabaseService.loadTrainers();
  final bookingsF = SupabaseService.loadBookings();
  final plansF = SupabaseService.loadMembershipPlans();
  final waiversF = SupabaseService.loadWaiverDocs();
  final platformSettingsF = SupabaseService.loadPlatformSettings();
  final profileF = SupabaseService.getSessionProfile();
  // Awaited one after another below; ignore() only stops a later one's
  // error counting as unhandled if an earlier one fails first.
  for (final f in [trainersF, bookingsF, plansF, waiversF, platformSettingsF, profileF]) {
    f.ignore();
  }

  // Background ones — the same ignore() reasoning; `later` still sees the
  // result or the error.
  final pointsLedgerF = SupabaseService.loadPointsLedgerAll()..ignore();
  final badgesF = SupabaseService.loadMeritBadgesAll()..ignore();
  final blockedTimeF = SupabaseService.loadBlockedTime()..ignore();
  final productsF = SupabaseService.loadProducts()..ignore();
  final couponsF = SupabaseService.loadCoupons()..ignore();
  final programsLibraryF = SupabaseService.loadProgramsLibrary()..ignore();
  final nutritionLibraryF = SupabaseService.loadNutritionLibrary()..ignore();
  final customMealsF = SupabaseService.loadCustomMeals()..ignore();
  final exercisesF = SupabaseService.loadExercises()..ignore();
  final challengesF = SupabaseService.loadChallenges()..ignore();
  final squadsF = SupabaseService.loadSquads()..ignore();
  final chargesF = SupabaseService.loadCharges()..ignore();
  final waitlistF = SupabaseService.loadWaitlist()..ignore();
  final packageCategoriesF = SupabaseService.loadPackageCategories()..ignore();
  final equipmentF = SupabaseService.loadEquipment()..ignore();
  final coachMeritBadgesF = SupabaseService.loadCoachMeritBadges()..ignore();
  final coachPrEventsF = SupabaseService.loadCoachPrEvents()..ignore();
  final messagesF = SupabaseService.loadAllMessages()..ignore();

  // ── Awaited phase ──
  final List<ClientInfo> roster;
  final List<Trainer> trainers;
  final List<Booking> bookings;
  final List<MembershipPlan> plans;
  final List<WaiverDoc> waivers;
  final PlatformSettings? platformSettings;
  final Map<String, ClientRecord> clientRecords;
  final Map<String, dynamic>? profile;
  try {
    roster = await rosterF;
    // Needs the roster's ids, so it's the one request that can't start
    // with the rest; it overlaps with the remaining awaits below.
    final clientRecordsF = SupabaseService.loadClientRecords(roster.map((c) => c.id).toList())..ignore();
    trainers = await trainersF;
    bookings = await bookingsF;
    plans = await plansF;
    waivers = await waiversF;
    platformSettings = await platformSettingsF;
    clientRecords = await clientRecordsF;
    profile = await profileF;
  } catch (e, st) {
    // Network unavailable, or RLS blocked one of these outright — leave
    // what's there rather than blanking every screen out.
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
  // Don't swap the built-in plans/waiver for an empty list before a gym has
  // defined its own — signup relies on the default waiver being there.
  if (plans.isNotEmpty) ref.read(membershipPlansProvider.notifier).setAll(plans);
  if (waivers.isNotEmpty) ref.read(waiversProvider.notifier).setAll(waivers);
  // Re-bound to a plain local: Dart doesn't carry the null-promotion of a
  // declared-then-assigned-in-try variable into the closure below.
  final resolvedSettings = platformSettings;
  if (resolvedSettings != null) {
    ref.read(platformSettingsProvider.notifier).update((_) => resolvedSettings);
  }
  ref.read(trainerClientRecordsProvider.notifier).setAll(clientRecords);

  // Sample-data defaults that the background phase replaces: clear them
  // now so the shell opens on nothing rather than on fake entries.
  final PointsLedgerNotifier pointsLedgerN = ref.read(pointsLedgerProvider.notifier)..setAll(const <PointsLedgerEntry>[]);
  final EarnedBadgesNotifier badgesN = ref.read(earnedBadgesProvider.notifier)..setAll(const <EarnedBadge>[]);
  final ChallengesNotifier challengesN = ref.read(challengesProvider.notifier)..setAll(const <Challenge>[]);
  final ChargesNotifier chargesN = ref.read(chargesProvider.notifier)..setAll(const <Charge>[]);
  // Read now, used after this function returns — see the note on `ref`.
  final BlockedTimesNotifier blockedTimesN = ref.read(blockedTimesProvider.notifier);
  final ProductsNotifier productsN = ref.read(productsProvider.notifier);
  final CouponsNotifier couponsN = ref.read(couponsProvider.notifier);
  final ProgramsLibraryNotifier programsLibraryN = ref.read(programsLibraryProvider.notifier);
  final NutritionLibraryNotifier nutritionLibraryN = ref.read(nutritionLibraryProvider.notifier);
  final CustomMealsNotifier customMealsN = ref.read(customMealsProvider.notifier);
  final ExerciseCatalogNotifier exercisesN = ref.read(exerciseCatalogProvider.notifier);
  final SquadsNotifier squadsN = ref.read(squadsProvider.notifier);
  final WaitlistNotifier waitlistN = ref.read(waitlistProvider.notifier);
  final PackageCategoriesNotifier packageCategoriesN = ref.read(packageCategoriesProvider.notifier);
  final EquipmentNotifier equipmentN = ref.read(equipmentProvider.notifier);
  final CoachMeritBadgesNotifier coachMeritBadgesN = ref.read(coachMeritBadgesProvider.notifier);
  final CoachPrEventsNotifier coachPrEventsN = ref.read(coachPrEventsProvider.notifier);
  final TrainerClientRecordsNotifier clientRecordsN = ref.read(trainerClientRecordsProvider.notifier);
  final ClientRecordNotifier ownRecordN = ref.read(clientRecordProvider.notifier);

  // ── Restore who's signed in from the current Supabase Auth session ──
  String? ownClientId;
  if (profile != null) {
    final role = profile["role"] as String?;
    final id = profile["id"] as String;

    if (role == "owner") {
      ref.read(roleProvider.notifier).set("trainer");
      ref.read(trainerAuthProvider.notifier).signIn("owner");
    } else if (role == "coach" && trainers.any((t) => t.id == id)) {
      ref.read(roleProvider.notifier).set("trainer");
      ref.read(trainerAuthProvider.notifier).signIn(id);
    } else if (role == "coach") {
      // A `profiles` row says "coach" but there's no matching `trainers`
      // row (e.g. left behind by the old coach-delete path that only ever
      // removed `trainers`, or a signup that never finished) — treat it as
      // a clear "signed out, sign in again" state rather than silently
      // authenticating into no role at all.
      await SupabaseService.signOut();
      return;
    } else if (role == "client") {
      final matches = roster.where((c) => c.id == id);
      if (matches.isEmpty) {
        // Session exists but their app-side row is gone — inert account.
        await SupabaseService.signOut();
        return;
      }
      ownClientId = id;
      ref.read(roleProvider.notifier).set("client");
      ref.read(clientInfoProvider.notifier).update((_) => matches.first);
      ref.read(clientRecordProvider.notifier).update((_) => clientRecords[id] ?? const ClientRecord(id: ""));
      ref.read(clientBookingsProvider.notifier).setAll(bookings.where((b) => b.clientId == id).toList());
      ref.read(clientSignedInProvider.notifier).signIn();
    }

    // Register this device for push now that we know who's signed in — the
    // token is stored against their profile. Never throws (see
    // PushService). Not awaited: it can sit on the OS permission prompt and
    // a token round trip, and the app shouldn't wait on either.
    unawaited(PushService.registerForCurrentUser());
  }

  // ── Background phase ──
  // Each result only applies if no newer load (a sign-out then a different
  // sign-in) has started since — a slow reply from the previous session
  // must not land on top of the next one's data.
  void later<T>(Future<T> f, String what, void Function(T) apply) {
    unawaited(f.then((v) {
      if (generation == _loadGeneration) apply(v);
    }).catchError((Object e) {
      // ignore: avoid_print
      print("[loadAndSeedCoreData] $what load failed: $e");
    }));
  }

  later(pointsLedgerF, "points", pointsLedgerN.setAll);
  later(badgesF, "badges", badgesN.setAll);
  later(challengesF, "challenges", challengesN.setAll);
  later(chargesF, "charges", chargesN.setAll);
  later(blockedTimeF, "blocked time", blockedTimesN.setAll);
  later(productsF, "products", productsN.setAll);
  later(couponsF, "coupons", couponsN.setAll);
  later(programsLibraryF, "programs", programsLibraryN.setAll);
  later(nutritionLibraryF, "nutrition", nutritionLibraryN.setAll);
  later(customMealsF, "custom meals", customMealsN.setAll);
  // Keep the curated catalog until a gym has entered exercises of its own.
  later(exercisesF, "exercises", (List<ExerciseDef> v) {
    if (v.isNotEmpty) exercisesN.setAll(v);
  });
  later(squadsF, "squads", squadsN.setAll);
  later(waitlistF, "waitlist", waitlistN.setAll);
  later(packageCategoriesF, "package categories", packageCategoriesN.setAll);
  later(equipmentF, "equipment", equipmentN.setAll);
  later(coachMeritBadgesF, "coach badges", coachMeritBadgesN.setAll);
  later(coachPrEventsF, "coach PR events", coachPrEventsN.setAll);
  // Chat lives in the `messages` table, not the record's jsonb; older
  // entries still in `comms` are kept and merged. The table's own policy
  // has already dropped blocked users' rows.
  final own = ownClientId;
  later(messagesF, "messages", (Map<String, List<CommMessage>> byClient) {
    clientRecordsN.mergeComms(byClient);
    final thread = own == null ? null : byClient[own];
    if (thread != null) {
      ownRecordN.update((r) {
        final byId = {for (final m in r.comms) m.id: m, for (final m in thread) m.id: m};
        return r.copyWith(comms: byId.values.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt)));
      });
    }
  });
}

/// Bumped by every [loadAndSeedCoreData] call; see `later` inside it.
int _loadGeneration = 0;

/// Re-reads membership state — plan, freeze, cancellation — from the
/// server so a change made on another device shows here. A signed-in
/// client refreshes their own row; staff refresh the roster ([onlyId]
/// limits that to one client). Called when the app comes back to the
/// foreground and by the `clients` realtime channel.
Future<void> refreshClientInfos(dynamic ref, {String? onlyId}) async {
  if (SupabaseService.currentUser == null) return;
  if (ref.read(clientSignedInProvider) == true) {
    final ownId = ref.read(clientInfoProvider).id as String;
    if (ownId.isEmpty || (onlyId != null && onlyId != ownId)) return;
    final fresh = await SupabaseService.loadClientById(ownId);
    if (fresh != null) ref.read(clientInfoProvider.notifier).update((_) => fresh);
    return;
  }
  if (ref.read(trainerAuthProvider) == null) return;
  if (onlyId != null) {
    final fresh = await SupabaseService.loadClientById(onlyId);
    if (fresh != null) ref.read(trainerRosterProvider.notifier).update(onlyId, (_) => fresh);
  } else {
    ref.read(trainerRosterProvider.notifier).setAll(await SupabaseService.loadRoster());
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
      billingShared: next.billingShared,
      chat: next.chat,
    );
  } catch (e) {
    return false;
  }
  ref.read(squadsProvider.notifier).update(squad.id, (_) => next);
  return true;
}

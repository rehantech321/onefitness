import "package:supabase_flutter/supabase_flutter.dart";
import "../../data/models/availability_block.dart";
import "../../data/models/blocked_time.dart";
import "../../data/models/booking.dart";
import "../../data/models/challenge.dart";
import "../../data/models/charge.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_plan.dart";
import "../../data/models/client_record.dart";
import "../../data/models/comm_message.dart";
import "../../data/models/earned_badge.dart";
import "../../data/models/exercise_def.dart";
import "../../data/models/exercise_prescription.dart";
import "../../data/models/intake_schema.dart";
import "../../data/models/meal_def.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/points_ledger_entry.dart";
import "../../data/models/product.dart";
import "../../data/models/program_day.dart";
import "../../data/models/saved_program.dart";
import "../../data/models/squad.dart";
import "../../data/models/trainer.dart";
import "../../data/models/trainer_note.dart";
import "../../data/models/waiver_doc.dart";
import "../../data/providers/platform_settings_provider.dart";
import "supabase_config.dart";

/// Thin wrapper around the real Supabase project (same backend the web app
/// uses), mirroring src/lib/supabaseData.js's field-name mapping 1:1 —
/// `profiles` (id/role/name/email/phone/photo_url) joined with the
/// role-specific `clients`/`trainers` table, `bookings`, and the
/// JSONB-blob `client_records` table.
///
/// Phase 1 scope: real Auth (sign in/out, session restore) plus read-only
/// roster/trainers/bookings/client-records. Writes and every other domain
/// (badges, points, memberships, reports, programs library, etc.) still run
/// on local mock state until a later phase moves them too — exactly the
/// same "Step 1: core entities only" migration order the web app itself
/// followed (see App.jsx's own comment to that effect).
class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  }

  static User? get currentUser => client.auth.currentUser;

  static Future<void> ensureSession() async {
    // Triggers supabase-js/supabase-flutter's session restore-from-storage
    // (and a token refresh if near-expired) before any RLS-protected query
    // fires — mirrors ensureSession() in supabaseData.js exactly; skipping
    // this is what caused "0 rows back, correct after a reload" there.
    // ignore: unused_local_variable
    final _ = client.auth.currentSession;
  }

  /// { id, role, name, email, phone, photo_url } or null if signed out /
  /// the account's app-side row was removed.
  static Future<Map<String, dynamic>?> getSessionProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await client.from("profiles").select().eq("id", user.id).maybeSingle();
    return row;
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Real self-signup — creates the auth account (a server-side trigger,
  /// handle_new_user in schema_phase1.sql, creates the matching `profiles`
  /// row from the `requested_role`/`name`/`phone` metadata passed here),
  /// then the `clients` row and a blank `client_records` row, mirroring
  /// signUpClient in supabaseData.js. Signing up also signs the new
  /// account in immediately (Supabase's default when email confirmation
  /// is off), matching the web app's own self-signup UX — the caller
  /// still needs to seed core data / restore state afterward, same as a
  /// normal sign-in.
  static Future<String> signUpClient({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? city,
    String? birthday,
  }) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {"requested_role": "client", "name": name, "phone": phone ?? ""},
    );
    final userId = res.user?.id;
    if (userId == null) throw Exception("Sign-up failed — no account was created.");
    await client.from("clients").insert({
      "profile_id": userId,
      if (city != null) "city": city,
      if (birthday != null) "birthday": birthday,
    });
    await client.from("client_records").insert({
      "profile_id": userId,
      "data": {"program": [], "logs": [], "comms": []},
    });
    return userId;
  }

  /// { code, expiresAt, generatedAt, usedAt } or null — the current staff
  /// approval code a prospective coach needs to self-signup. No UI exists
  /// yet to generate/rotate this (see Part 7's own scoping note); it's
  /// whatever the owner most recently set directly.
  static Future<Map<String, dynamic>?> loadCoachApprovalCode() async {
    return client.from("coach_approval_code").select().maybeSingle();
  }

  /// Real coach self-signup — mirrors signUpCoach in supabaseData.js.
  /// `reviewed_by_owner: false` for self-signup (an owner adding a coach
  /// directly would pass true, but that flow isn't built here — see
  /// coaches_overview_screen.dart's own "mocked" note). Spending the
  /// approval code is best-effort — same as the source: the account
  /// already exists by the time this RPC runs regardless of its outcome,
  /// so a race here shouldn't fail an otherwise-successful signup.
  static Future<String> signUpCoach({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String approvalCode,
  }) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {"requested_role": "coach", "name": name, "phone": phone ?? ""},
    );
    final userId = res.user?.id;
    if (userId == null) throw Exception("Sign-up failed — no account was created.");
    await client.from("trainers").insert({"profile_id": userId, "reviewed_by_owner": false});
    try {
      await client.rpc("mark_coach_code_used", params: {"entered_code": approvalCode});
    } catch (e) {
      // ignore: avoid_print
      print("[SupabaseService] mark_coach_code_used failed: $e");
    }
    return userId;
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  // ── Read ──────────────────────────────────────────────────────────

  /// A single client's own ClientInfo — used right after sign-in, so the
  /// client doesn't need the whole-gym roster fetched first just to find
  /// their own row in it.
  static Future<ClientInfo?> loadClientById(String id) async {
    final profile = await client.from("profiles").select().eq("id", id).maybeSingle();
    if (profile == null) return null;
    final c = await client.from("clients").select().eq("profile_id", id).maybeSingle();
    return _clientInfoFromRow(profile, c ?? const {});
  }

  static Future<List<ClientInfo>> loadRoster() async {
    final profiles = await client.from("profiles").select().eq("role", "client");
    if (profiles.isEmpty) return [];
    final ids = profiles.map((p) => p["id"] as String).toList();
    final clients = await client.from("clients").select().inFilter("profile_id", ids);
    final byId = {for (final c in clients) c["profile_id"] as String: c};
    return _safeMap(profiles, (p) => _clientInfoFromRow(p, byId[p["id"]] ?? const {}));
  }

  static Future<List<Trainer>> loadTrainers() async {
    final profiles = await client.from("profiles").select().eq("role", "coach");
    if (profiles.isEmpty) return [];
    final ids = profiles.map((p) => p["id"] as String).toList();
    final trainers = await client.from("trainers").select().inFilter("profile_id", ids);
    final byId = {for (final t in trainers) t["profile_id"] as String: t};
    final withRow = profiles.where((p) => byId.containsKey(p["id"]));
    return _safeMap(withRow, (p) => _trainerFromRow(p, byId[p["id"]]!));
  }

  static Future<List<Booking>> loadBookings() async {
    final rows = await client.from("bookings").select();
    return _safeMap(rows, _bookingFromRow);
  }

  static Future<ClientRecord> loadClientRecord(String id) async {
    final row = await client.from("client_records").select("data").eq("profile_id", id).maybeSingle();
    final data = (row?["data"] as Map?)?.cast<String, dynamic>() ?? const {};
    return _clientRecordFromJson(id, data);
  }

  /// Owner-edited membership plans (jsonb-blob-per-row, same convention as
  /// products/waiver_docs/programs_library/custom_meals — id + a `data`
  /// blob whose keys are already camelCase, unlike the normalized tables).
  static Future<List<MembershipPlan>> loadMembershipPlans() async {
    final rows = await client.from("membership_plans").select();
    return _safeMap(rows, (r) => _membershipPlanFromJson((r["data"] as Map).cast<String, dynamic>()));
  }

  /// Roster-wide — RLS (points_ledger_select_self_or_staff) scopes what
  /// actually comes back to whatever the caller may see either way.
  static Future<List<PointsLedgerEntry>> loadPointsLedgerAll() async {
    final rows = await client.from("points_ledger").select();
    return _safeMap(rows, _pointsLedgerFromRow);
  }

  static Future<List<EarnedBadge>> loadMeritBadgesAll() async {
    final rows = await client.from("merit_badges").select();
    return _safeMap(rows, _earnedBadgeFromRow);
  }

  /// Re-fetches just one client's rows after a points/badge mutation — used
  /// instead of trusting a locally-reconstructed row, since the server
  /// computes the real id/expiry/cap-checked amount (see grant-points'
  /// insert) that a client-guessed value can't replicate.
  static Future<List<PointsLedgerEntry>> loadPointsLedgerFor(String clientId) async {
    final rows = await client.from("points_ledger").select().eq("client_id", clientId);
    return _safeMap(rows, _pointsLedgerFromRow);
  }

  static Future<List<EarnedBadge>> loadMeritBadgesFor(String clientId) async {
    final rows = await client.from("merit_badges").select().eq("client_id", clientId);
    return _safeMap(rows, _earnedBadgeFromRow);
  }

  /// Unfiltered, unlike loadBlockedTimeInRange's date-windowed query in
  /// supabaseData.js — this app doesn't do windowed fetches anywhere yet
  /// (same as loadBookings), and RLS scopes what a trainer/owner can see
  /// regardless of any client-side date filter.
  static Future<List<BlockedTime>> loadBlockedTime() async {
    final rows = await client.from("blocked_time").select();
    return _safeMap(rows, _blockedTimeFromRow);
  }

  static BlockedTime _blockedTimeFromRow(Map<String, dynamic> row) => BlockedTime(
        id: row["id"].toString(),
        trainerId: row["trainer_id"] as String,
        date: row["date"] as String,
        allDay: row["full_day"] as bool? ?? true,
        startMin: _asInt(row["start_min"]),
        endMin: _asInt(row["end_min"]),
        reason: row["reason"] as String?,
      );

  /// Real timestamp columns come back as full ISO-with-time
  /// (`2026-08-04T11:14:33.05+00:00`); every date-comparison util and every
  /// display site was built against mock data's plain `yyyy-MM-dd` strings.
  /// `DateTime.parse` handles both equally well for ordering/comparison, so
  /// truncating here (once, at the boundary) keeps every downstream site
  /// unchanged instead of reformatting at each of the several places these
  /// fields are displayed.
  static String? _dateOnly(String? iso) => (iso != null && iso.length >= 10) ? iso.substring(0, 10) : iso;

  static PointsLedgerEntry _pointsLedgerFromRow(Map<String, dynamic> row) => PointsLedgerEntry(
        id: row["id"].toString(),
        clientId: row["client_id"] as String,
        amount: _asInt(row["amount"]) ?? 0,
        type: row["type"] as String? ?? "",
        source: row["source"] as String? ?? "",
        createdAt: _dateOnly(row["created_at"] as String?) ?? "",
        expiresAt: _dateOnly(row["expires_at"] as String?),
        grantedByUserId: row["granted_by_user_id"] as String?,
        reason: row["reason"] as String?,
        voidedByLedgerId: row["voided_by_ledger_id"]?.toString(),
      );

  static EarnedBadge _earnedBadgeFromRow(Map<String, dynamic> row) => EarnedBadge(
        id: row["id"].toString(),
        clientId: row["client_id"] as String,
        badgeKey: row["badge_key"] as String,
        earnedAt: _dateOnly(row["earned_at"] as String?) ?? "",
        earnedMethod: row["earned_method"] as String? ?? "automatic",
        grantedByUserId: row["granted_by_user_id"] as String?,
        note: row["note"] as String?,
        revokedAt: _dateOnly(row["revoked_at"] as String?),
        revokedByUserId: row["revoked_by_user_id"] as String?,
      );

  static Future<List<Product>> loadProducts() async {
    final rows = await client.from("products").select();
    return _safeMap(rows, (r) => _productFromJson((r["data"] as Map).cast<String, dynamic>()));
  }

  static Product _productFromJson(Map<String, dynamic> j) => Product(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        priceCents: _asInt(j["priceCents"]) ?? 0,
        category: j["category"] as String?,
        archived: j["archived"] as bool? ?? false,
      );

  static Future<List<WaiverDoc>> loadWaiverDocs() async {
    final rows = await client.from("waiver_docs").select();
    return _safeMap(rows, (r) => _waiverDocFromJson((r["data"] as Map).cast<String, dynamic>()));
  }

  static WaiverDoc _waiverDocFromJson(Map<String, dynamic> j) => WaiverDoc(
        id: j["id"] as String,
        title: j["title"] as String? ?? "",
        body: j["body"] as String? ?? "",
        scope: j["scope"] as String? ?? "general",
        planId: j["planId"] as String?,
        required: j["required"] as bool? ?? true,
        archived: j["archived"] as bool? ?? false,
      );

  /// `programs_library` holds both workout and nutrition templates in the
  /// same table, distinguished by `data.type` — this app's nutrition-side
  /// library (NutritionLibraryEntry, wrapping the far more complex legacy
  /// NutritionPlan shape) isn't verified against any real populated row, so
  /// only `type: "workout"` entries are mapped here for now; a nutrition
  /// row is skipped rather than guessed.
  static Future<List<SavedProgram>> loadProgramsLibrary() async {
    final rows = await client.from("programs_library").select();
    final out = <SavedProgram>[];
    for (final row in rows) {
      try {
        final data = ((row as Map)["data"] as Map).cast<String, dynamic>();
        if ((data["type"] as String?) == "nutrition") continue;
        out.add(_savedProgramFromJson(data));
      } catch (e) {
        // ignore: avoid_print
        print("[SupabaseService] skipped malformed programs_library row: $e — $row");
      }
    }
    return out;
  }

  static SavedProgram _savedProgramFromJson(Map<String, dynamic> j) => SavedProgram(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        status: j["status"] as String? ?? "active",
        // `createdBy` holds the coach's display *name*, not a user id — a
        // naming quirk carried over verbatim from SaveProgramDialog.jsx's
        // own entry shape (confirmed against a real row).
        coachName: j["createdBy"] as String?,
        programDays: _safeMap(((j["programDays"] as List?) ?? const []).whereType<Map>(), _programDayFromJson),
      );

  static ProgramDay _programDayFromJson(Map<String, dynamic> j) => ProgramDay(
        id: j["id"] as String,
        title: j["title"] as String? ?? "",
        exercises: _safeMap(((j["exercises"] as List?) ?? const []).whereType<Map>(), _exercisePrescriptionFromJson),
      );

  static ExercisePrescription _exercisePrescriptionFromJson(Map<String, dynamic> j) => ExercisePrescription(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        exerciseId: j["exerciseId"] as String?,
        group: j["group"] as String?,
        sets: _asInt(j["sets"]) ?? 3,
        reps: _asInt(j["reps"]) ?? 0,
        weight: j["weight"]?.toString(),
        time: j["time"]?.toString(),
        distance: j["distance"]?.toString(),
        rest: j["rest"]?.toString(),
        notes: j["notes"] as String?,
        laterality: j["laterality"] as String? ?? "bilateral",
        supersetId: j["supersetId"] as String?,
      );

  static Future<List<MealDef>> loadCustomMeals() async {
    final rows = await client.from("custom_meals").select();
    return _safeMap(rows, (r) => _mealDefFromJson((r["data"] as Map).cast<String, dynamic>()));
  }

  static MealDef _mealDefFromJson(Map<String, dynamic> j) => MealDef(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        mealType: j["mealType"] as String? ?? "snacks",
        calories: _asInt(j["calories"]) ?? 0,
        protein: (j["protein"] as num?)?.toDouble() ?? 0,
        carbs: (j["carbs"] as num?)?.toDouble() ?? 0,
        fats: (j["fats"] as num?)?.toDouble() ?? 0,
        ingredients: ((j["ingredients"] as List?) ?? const []).whereType<String>().toList(),
        instructions: j["instructions"] as String?,
        dietTags: ((j["dietTags"] as List?) ?? const []).whereType<String>().toList(),
        isCustom: j["isCustom"] as bool? ?? true,
      );

  /// Real data's key is `equipmentIds`, not `equipment` (confirmed against a
  /// real row) — this model's field is named for what it holds, not for the
  /// wire format. `movementPattern`/`primaryMuscle` values in real data
  /// ("horizontal-pull", "olympic") also don't match this app's
  /// kMovementPatterns/kMuscleGroups picklists (built for the mock catalog);
  /// harmless — the edit form's chip picker just shows nothing pre-selected
  /// for those two fields until the coach picks one, same as any unrecognized
  /// value would.
  static Future<List<ExerciseDef>> loadExercises() async {
    final rows = await client.from("exercises").select();
    return _safeMap(rows, (r) => _exerciseDefFromJson((r["data"] as Map).cast<String, dynamic>()));
  }

  static ExerciseDef _exerciseDefFromJson(Map<String, dynamic> j) => ExerciseDef(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        movementPattern: j["movementPattern"] as String? ?? "",
        primaryMuscle: j["primaryMuscle"] as String? ?? "",
        equipment: ((j["equipmentIds"] as List?) ?? const []).whereType<String>().toList(),
        setup: j["setup"] as String?,
        cues: j["cues"] as String?,
        coachNotes: j["coachNotes"] as String?,
      );

  static Future<List<Challenge>> loadChallenges() async {
    final rows = await client.from("challenges").select();
    return _safeMap(rows, _challengeFromRow);
  }

  /// `description`/`prize` are `not null default ''` on the real table
  /// (confirmed against a real row) — the model's own UI treats "no prize"
  /// as `null` (`if (challenge.prize != null)` gates the prize card), so an
  /// empty string has to be normalized to null on the way in or a real
  /// challenge with no prize would render a blank prize card.
  static String? _emptyToNull(dynamic v) => (v is String && v.isNotEmpty) ? v : null;

  static Challenge _challengeFromRow(Map<String, dynamic> row) => Challenge(
        id: row["id"] as String,
        name: row["name"] as String? ?? "",
        template: row["template"] as String? ?? "",
        metric: row["metric"] as String? ?? "",
        startDate: row["start_date"] as String? ?? "",
        endDate: row["end_date"] as String? ?? "",
        description: _emptyToNull(row["description"]),
        prize: _emptyToNull(row["prize"]),
        participantIds: ((row["participants"] as List?) ?? const []).whereType<String>().toList(),
        winnerClientId: row["winner"] as String?,
      );

  static Future<List<Squad>> loadSquads() async {
    final rows = await client.from("squads").select();
    return _safeMap(rows, _squadFromRow);
  }

  static Squad _squadFromRow(Map<String, dynamic> row) => Squad(
        id: row["id"] as String,
        name: row["name"] as String?,
        leadId: row["lead_id"] as String,
        memberIds: ((row["member_ids"] as List?) ?? const []).whereType<String>().toList(),
        memberMeta: ((row["member_meta"] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, _squadMemberMetaFromJson((v as Map).cast<String, dynamic>())),
        ),
        maxSize: _asInt(row["max_size"]) ?? kDefaultSquadMax,
        membership: row["membership"] != null ? _squadMembershipFromJson((row["membership"] as Map).cast<String, dynamic>()) : null,
        pendingInvites: _safeMap(((row["pending_invites"] as List?) ?? const []).whereType<Map>(), _squadInviteFromJson),
        activity: _safeMap(((row["activity"] as List?) ?? const []).whereType<Map>(), _squadActivityFromJson),
      );

  static SquadMemberMeta _squadMemberMetaFromJson(Map<String, dynamic> j) => SquadMemberMeta(
        relationship: j["relationship"] as String? ?? "",
        status: j["status"] as String? ?? "active",
        paymentEnabled: j["paymentEnabled"] as bool? ?? false,
        minBalance: (j["minBalance"] as num?) ?? 0,
      );

  static SquadInvite _squadInviteFromJson(Map<String, dynamic> j) => SquadInvite(
        clientId: j["clientId"] as String,
        sentAt: j["sentAt"] as String? ?? "",
        status: j["status"] as String? ?? "pending",
      );

  /// Real rows nest the human-readable text one level deeper than this
  /// model does — `activity[i].details.description`, not a flat
  /// `activity[i].description` (confirmed against a real row).
  static SquadActivityEntry _squadActivityFromJson(Map<String, dynamic> j) => SquadActivityEntry(
        id: j["id"] as String,
        type: j["type"] as String? ?? "",
        at: j["at"] as String? ?? "",
        actorName: j["actorName"] as String?,
        description: (j["details"] as Map?)?["description"] as String?,
      );

  static SquadMembership _squadMembershipFromJson(Map<String, dynamic> j) => SquadMembership(
        planName: j["planName"] as String? ?? "",
        kind: j["kind"] as String? ?? "package",
        sessionsRemaining: _asInt(j["sessionsRemaining"]) ?? 0,
        sessionsTotal: _asInt(j["sessionsTotal"]) ?? 0,
        renewalDate: j["renewalDate"] as String?,
      );

  static Future<List<Charge>> loadCharges() async {
    final rows = await client.from("charges").select();
    return _safeMap(rows, _chargeFromRow);
  }

  static Charge _chargeFromRow(Map<String, dynamic> row) => Charge(
        id: row["id"] as String,
        clientId: row["client_id"] as String,
        clientName: row["client_name"] as String? ?? "",
        type: row["type"] as String? ?? "",
        date: row["date"] as String? ?? "",
        amount: (row["amount"] as num?)?.toDouble(),
        category: row["category"] as String?,
        description: row["description"] as String?,
        planId: row["plan_id"] as String?,
        planName: row["plan_name"] as String?,
        trainerId: row["trainer_id"] as String?,
        trainerName: row["trainer_name"] as String?,
        waivedAt: _dateOnly(row["waived_at"] as String?),
      );

  /// Real `data` blob nests everything under 5 tabs (`access`, `clients`,
  /// `payments`, `workouts`, `scheduling` — note the coach-related tab is
  /// called "access" in the database, not "coaches" like the settings
  /// screen's own UI tab label) and carries several fields this app's
  /// PlatformSettings model doesn't track at all (customProfileFields,
  /// requiredProfileFields, feeLabel, businessTimeZone, bookingCoachScope,
  /// applyToAch/Debit/Credit, feeFlatCents, feeStructure, showFeeLineItem,
  /// refundFeeOnRefund, checkoutDisclosureText, blockRescheduleInWindow,
  /// lateCancellationFeeCents — all confirmed against a real row). Returns
  /// null if no row exists yet, in which case the caller keeps the model's
  /// own defaults (same as every other "real, even if absent" domain here).
  static Future<PlatformSettings?> loadPlatformSettings() async {
    final row = await client.from("platform_settings").select("data").eq("id", "global").maybeSingle();
    if (row == null) return null;
    return _platformSettingsFromJson((row["data"] as Map).cast<String, dynamic>());
  }

  static PlatformSettings _platformSettingsFromJson(Map<String, dynamic> j) {
    final access = ((j["access"] as Map?) ?? const {}).cast<String, dynamic>();
    final clients = ((j["clients"] as Map?) ?? const {}).cast<String, dynamic>();
    final payments = ((j["payments"] as Map?) ?? const {}).cast<String, dynamic>();
    final workouts = ((j["workouts"] as Map?) ?? const {}).cast<String, dynamic>();
    final scheduling = ((j["scheduling"] as Map?) ?? const {}).cast<String, dynamic>();
    const defaults = PlatformSettings();
    return PlatformSettings(
      lateCancellationHours: _asInt(scheduling["lateCancellationHours"]) ?? defaults.lateCancellationHours,
      maxBookingHorizonDays: _asInt(scheduling["maxBookingHorizonDays"]) ?? defaults.maxBookingHorizonDays,
      minBookingLeadHours: _asInt(scheduling["minBookingLeadHours"]) ?? defaults.minBookingLeadHours,
      semiPrivateCap: _asInt(scheduling["semiPrivateCap"]) ?? defaults.semiPrivateCap,
      twoFactorRequirement: access["twoFactorRequirement"] as String? ?? defaults.twoFactorRequirement,
      coachClientScope: access["coachClientScope"] as String? ?? defaults.coachClientScope,
      coachCanViewRevenue: access["coachCanViewRevenue"] as bool? ?? defaults.coachCanViewRevenue,
      coachCanSeeOtherSchedules: access["coachCanSeeOtherSchedules"] as bool? ?? defaults.coachCanSeeOtherSchedules,
      coachCanEditClientWorkouts: access["coachCanEditClientWorkouts"] as bool? ?? defaults.coachCanEditClientWorkouts,
      messageIdentity: access["messageIdentity"] as String? ?? defaults.messageIdentity,
      requireWaiverAtSignup: clients["requireWaiverAtSignup"] as bool? ?? defaults.requireWaiverAtSignup,
      clientsCanMessageAnyCoach: clients["clientsCanMessageAnyCoach"] as bool? ?? defaults.clientsCanMessageAnyCoach,
      processingFeeEnabled: payments["processingFeeEnabled"] as bool? ?? defaults.processingFeeEnabled,
      feePercent: (payments["feePercent"] as num?) ?? defaults.feePercent,
      autoCarryOverLastWeight: workouts["autoCarryOverLastWeight"] as bool? ?? defaults.autoCarryOverLastWeight,
      defaultWeightUnit: workouts["defaultWeightUnit"] as String? ?? defaults.defaultWeightUnit,
      clientsCanSwapExercises: workouts["clientsCanSwapExercises"] as bool? ?? defaults.clientsCanSwapExercises,
      businessName: workouts["businessName"] as String? ?? defaults.businessName,
    );
  }

  // ── Write ─────────────────────────────────────────────────────────

  /// A client editing their own profile (name/email/phone live on
  /// `profiles`, city on `clients`) — mirrors updateClientRow's field split
  /// in supabaseData.js, trimmed to the fields the app's Edit Profile screen
  /// actually exposes.
  static Future<void> updateClientRow(String id, {String? name, String? email, String? phone, String? city, String? membershipPlanId}) async {
    final profileFields = <String, dynamic>{
      if (name != null) "name": name,
      if (email != null) "email": email,
      if (phone != null) "phone": phone,
    };
    if (profileFields.isNotEmpty) await client.from("profiles").update(profileFields).eq("id", id);
    final clientFields = <String, dynamic>{
      if (city != null) "city": city,
      if (membershipPlanId != null) "membership_plan_id": membershipPlanId,
    };
    if (clientFields.isNotEmpty) await client.from("clients").update(clientFields).eq("profile_id", id);
  }

  /// A coach editing their own profile. `locations` is a list on the real
  /// schema (see `_locationNameFrom`'s doc comment on `bookings.location`
  /// for the same shape) — the app only edits a single location, so it's
  /// always written back as a one-item list.
  static Future<void> updateTrainerRow(
    String id, {
    String? name,
    String? email,
    String? phone,
    String? locationName,
    String? locationAddress,
    List<AvailabilityBlock>? availability,
  }) async {
    final profileFields = <String, dynamic>{
      if (name != null) "name": name,
      if (email != null) "email": email,
      if (phone != null) "phone": phone,
    };
    if (profileFields.isNotEmpty) await client.from("profiles").update(profileFields).eq("id", id);
    final trainerFields = <String, dynamic>{
      if (locationName != null || locationAddress != null)
        "locations": [
          {"id": "loc-main", "name": locationName ?? "", "address": locationAddress ?? ""},
        ],
      if (availability != null) "availability": availability.map(_availabilityToJson).toList(),
    };
    if (trainerFields.isNotEmpty) await client.from("trainers").update(trainerFields).eq("profile_id", id);
  }

  static Map<String, dynamic> _availabilityToJson(AvailabilityBlock b) => {
        "sessionType": b.sessionType,
        "discipline": b.discipline,
        "byDay": b.byDay.map((weekday, slots) => MapEntry(weekday.toString(), slots)),
      };

  /// `client_records.data` is a single JSONB column holding many features'
  /// worth of state (see ClientRecord's own doc comment) — upsert replaces
  /// the whole column, so every write here re-fetches the current blob and
  /// merges the patch on top rather than reconstructing it from this app's
  /// (currently partial) ClientRecord model, to avoid silently dropping
  /// fields this app doesn't model yet (program/logs/tourSeen/...).
  static Future<void> upsertClientRecordPatch(String profileId, Map<String, dynamic> patch) async {
    final row = await client.from("client_records").select("data").eq("profile_id", profileId).maybeSingle();
    final current = (row?["data"] as Map?)?.cast<String, dynamic>() ?? const {};
    final next = {...current, ...patch};
    await client.from("client_records").upsert({"profile_id": profileId, "data": next});
  }

  static Map<String, dynamic> _commMessageToJson(CommMessage m) => {
        "id": m.id,
        "who": m.who,
        "text": m.text,
        "at": m.at,
        "trainerId": m.trainerId,
        "readByCoach": m.readByCoach,
      };

  static Future<void> updateClientComms(String profileId, List<CommMessage> comms) =>
      upsertClientRecordPatch(profileId, {"comms": comms.map(_commMessageToJson).toList()});

  static Map<String, dynamic> _trainerNoteToJson(TrainerNote n) => {
        "id": n.id,
        "flag": n.flag,
        "title": n.title,
        "details": n.details,
        "coachId": n.coachId,
        "coachName": n.coachName,
        "createdAt": n.createdAt,
        "modifiedAt": n.modifiedAt,
        "status": n.status,
        "bodyArea": n.bodyArea,
        "followUpRequired": n.followUpRequired,
        "resolveBy": n.resolveBy,
      };

  static Future<void> updateClientTrainerNotes(String profileId, List<TrainerNote> notes) =>
      upsertClientRecordPatch(profileId, {"trainerNotes": notes.map(_trainerNoteToJson).toList()});

  /// Assigning a program to a client (ProgramBuilder.jsx) writes both here
  /// (this client's own copy) and a separate copy into the shared
  /// programs_library — see upsertProgramLibraryEntry.
  static Future<void> updateClientSavedPrograms(String profileId, List<SavedProgram> programs) =>
      upsertClientRecordPatch(profileId, {"savedPrograms": programs.map(_savedProgramToJson).toList()});

  /// `client_records.data.challengeProgress` — keyed by challenge id, each a
  /// list of manually-logged entries (ClientChallengeDetail.jsx). Not
  /// verified against a real populated record (every real one seen so far
  /// is empty here), but it's a simple, single-shape field — unlike the
  /// program/logs vs savedPrograms/workoutLogs ambiguity that held up Part
  /// 1, there's no competing second system for this one in the JS source.
  static Future<void> updateClientChallengeProgress(String profileId, Map<String, List<ChallengeProgressEntry>> progress) =>
      upsertClientRecordPatch(profileId, {
        "challengeProgress": progress.map((k, v) => MapEntry(k, v.map((e) => {"value": e.value, "loggedAt": e.loggedAt}).toList())),
      });

  /// `client_records.data.intake` is itself keyed by assessment
  /// ("personalTraining" | "nutritional" | ...) — a plain
  /// upsertClientRecordPatch({"intake": {...}}) would replace that whole
  /// object and wipe out every other already-submitted form, so this reads
  /// the current nested map, merges just the one key, and writes the full
  /// blob back (same fetch-then-merge shape as upsertClientRecordPatch
  /// itself, one level deeper).
  static Future<void> updateClientIntake(String profileId, String assessmentKey, IntakeRecord record) async {
    final row = await client.from("client_records").select("data").eq("profile_id", profileId).maybeSingle();
    final current = (row?["data"] as Map?)?.cast<String, dynamic>() ?? const {};
    final currentIntake = (current["intake"] as Map?)?.cast<String, dynamic>() ?? const {};
    final nextIntake = {
      ...currentIntake,
      assessmentKey: {
        "answers": record.answers,
        "completed": record.completed,
        "at": record.at,
        "by": record.by,
      },
    };
    await client.from("client_records").upsert({"profile_id": profileId, "data": {...current, "intake": nextIntake}});
  }

  /// Inserts and returns the server-assigned row (real id, defaults applied)
  /// — mirrors insertBooking in supabaseData.js. `location` only ever
  /// round-trips a bare name here since that's all `Booking.locationName`
  /// carries; see `_locationNameFrom`.
  static Future<Booking> insertBooking(Booking b) async {
    final row = {
      "client_id": b.clientId,
      "trainer_id": b.trainerId,
      "date": b.date,
      "slot_min": b.slot,
      "session_type": b.sessionType,
      "discipline": b.discipline,
      "location": b.locationName != null ? {"name": b.locationName} : null,
      "is_physical_assessment": b.isPhysicalAssessment,
    };
    final data = await client.from("bookings").insert(row).select().single();
    return _bookingFromRow(data);
  }

  static Future<void> deleteBooking(String id) async {
    await client.from("bookings").delete().eq("id", id);
  }

  /// `created_by` defaults server-side to auth.uid() — the owner's app-side
  /// identifier is the literal string "owner", not their real uuid, so it's
  /// never sent from here (same reasoning as insertBlockedTime's JS
  /// counterpart).
  static Future<BlockedTime> insertBlockedTime(BlockedTime bt) async {
    final row = {
      "trainer_id": bt.trainerId,
      "date": bt.date,
      "start_min": bt.allDay ? null : bt.startMin,
      "end_min": bt.allDay ? null : bt.endMin,
      "full_day": bt.allDay,
      "reason": bt.reason,
    };
    final data = await client.from("blocked_time").insert(row).select().single();
    return _blockedTimeFromRow(data);
  }

  static Future<void> updateBookingAttendance(String id, String? status) async {
    await client.from("bookings").update({"attendance_status": status}).eq("id", id);
  }

  /// There is no insert/update/delete RLS policy on `points_ledger` or
  /// `merit_badges` for any role, by design (see grant-points/index.ts's own
  /// doc comment) — every write to either table has to go through one of
  /// these Edge Functions, which run under the service role after doing
  /// their own auth/role/cap checks server-side. `FunctionsHttpException`'s
  /// `details` is already-decoded JSON (unlike supabase-js, which hands
  /// back a raw Response the caller has to parse), so unwrapping the
  /// function's own `{error: "..."}` body is a lot less code than
  /// supabaseData.js's `invokeFunctionOrThrow` needs.
  static Future<Map<String, dynamic>> _invokeFunction(String name, Map<String, dynamic> body) async {
    try {
      final res = await client.functions.invoke(name, body: body);
      final data = res.data;
      return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      final detail = details is Map ? details["error"]?.toString() : null;
      throw Exception(detail ?? e.reasonPhrase ?? "Request failed.");
    }
  }

  /// Coach/owner discretionary grant — amount must be 1, 3, or 5; reason
  /// required (min 5 chars). Server enforces the 5/month/coach/client cap.
  static Future<void> grantPoints(String clientId, int amount, String reason) =>
      _invokeFunction("grant-points", {"clientId": clientId, "amount": amount, "reason": reason});

  /// Voids one specific prior earn/grant row. reason required.
  static Future<void> voidPoints(String ledgerRowId, String reason) =>
      _invokeFunction("void-points", {"ledgerRowId": ledgerRowId, "reason": reason});

  /// Owner-only general point removal (FIFO, no specific row targeted).
  static Future<void> deductPoints(String clientId, int amount, String reason) =>
      _invokeFunction("deduct-points", {"clientId": clientId, "amount": amount, "reason": reason});

  /// Redeems points against an ALREADY-ACTIVE Stripe subscription — fails
  /// with a clear message for any client without one (package/program
  /// plans, or a membership plan never actually checked out through
  /// real Stripe), which is expected until Part 8 wires real payments.
  static Future<Map<String, dynamic>> redeemPoints(String clientId) => _invokeFunction("redeem-points", {"clientId": clientId});

  /// Coach/owner manual award — badgeKey must be one of MERIT_BADGES'
  /// category:"coach" entries (Record Breaker, Gym Citizen).
  static Future<Map<String, dynamic>> grantMeritBadge(String clientId, String badgeKey, String? note) =>
      _invokeFunction("grant-merit-badge", {"clientId": clientId, "badgeKey": badgeKey, if (note != null) "note": note});

  /// Owner-only override — any of the 11 catalog badges, bypassing all
  /// eligibility checks.
  static Future<Map<String, dynamic>> forceAwardMeritBadge(String clientId, String badgeKey, String? note) =>
      _invokeFunction("force-award-merit-badge", {"clientId": clientId, "badgeKey": badgeKey, if (note != null) "note": note});

  /// Coach/owner-only removal — only ever allowed for a coach-awarded badge;
  /// the server re-verifies this itself. Soft-delete (revoked_at set).
  static Future<void> revokeMeritBadge(String badgeId) => _invokeFunction("revoke-merit-badge", {"badgeId": badgeId});

  /// Owner-only real Stripe refund (test-mode key in this project) — only
  /// valid for a `type: "purchase"` charge with a linked
  /// stripe_payment_intent_id. Inserts a new negative-amount "refund" row
  /// rather than modifying the original charge, so the caller should
  /// re-fetch (loadCharges) rather than mutate the refunded row locally.
  static Future<Map<String, dynamic>> refundCharge(String chargeId) => _invokeFunction("refund-charge", {"chargeId": chargeId});

  /// Owner-only — only valid for a `type: "early_termination_fee"` charge;
  /// marks the existing row waived in place (unlike refund, no new row).
  static Future<void> waiveCharge(String chargeId) => _invokeFunction("waive-charge", {"chargeId": chargeId});

  /// Real email, sent server-side via the send-email Edge Function (SMTP —
  /// see supabase/EMAIL_SETUP.md). Any authenticated caller may invoke this
  /// (Comms.jsx/CoachChat.jsx's "Email"/"Both" channel is available to both
  /// clients and coaches) — there's no role restriction to enforce here.
  static Future<void> sendEmail({required String to, required String subject, required String text}) =>
      _invokeFunction("send-email", {"to": to, "subject": subject, "text": text});

  /// Real Stripe Checkout — mirrors createCheckoutSession in
  /// supabaseData.js, trimmed to card payments only (this app doesn't
  /// model the platform-settings ACH-availability toggle) and without the
  /// referral-email step (a growth-marketing nicety, not core to "can a
  /// client buy a plan"). Returns the Stripe-hosted Checkout URL to send
  /// the browser to — the plan is only ever actually granted later, by
  /// stripe-webhook confirming payment, never here and never client-side.
  static Future<String> createCheckoutSession({required String planId, required String returnUrl}) async {
    final data = await _invokeFunction("create-checkout-session", {
      "planId": planId,
      "returnUrl": returnUrl,
      "paymentMethod": "card",
    });
    final url = data["url"] as String?;
    if (url == null) throw Exception("Couldn't start checkout.");
    return url;
  }

  static Map<String, Map<String, dynamic>> _platformSettingsTabPatch(PlatformSettings s) => {
        "access": {
          "messageIdentity": s.messageIdentity,
          "coachClientScope": s.coachClientScope,
          "coachCanViewRevenue": s.coachCanViewRevenue,
          "twoFactorRequirement": s.twoFactorRequirement,
          "coachCanSeeOtherSchedules": s.coachCanSeeOtherSchedules,
          "coachCanEditClientWorkouts": s.coachCanEditClientWorkouts,
        },
        "clients": {
          "requireWaiverAtSignup": s.requireWaiverAtSignup,
          "clientsCanMessageAnyCoach": s.clientsCanMessageAnyCoach,
        },
        "payments": {
          "processingFeeEnabled": s.processingFeeEnabled,
          "feePercent": s.feePercent,
        },
        "workouts": {
          "businessName": s.businessName,
          "defaultWeightUnit": s.defaultWeightUnit,
          "autoCarryOverLastWeight": s.autoCarryOverLastWeight,
          "clientsCanSwapExercises": s.clientsCanSwapExercises,
        },
        "scheduling": {
          "semiPrivateCap": s.semiPrivateCap,
          "minBookingLeadHours": s.minBookingLeadHours,
          "lateCancellationHours": s.lateCancellationHours,
          "maxBookingHorizonDays": s.maxBookingHorizonDays,
        },
      };

  /// Owner-only. Merges this model's ~17 fields into whatever tab maps
  /// already exist in the real blob (re-fetched fresh, same reasoning as
  /// upsertClientRecordPatch) rather than overwriting `data` outright — the
  /// real row carries ~15 additional fields this app doesn't model, and a
  /// blind overwrite would silently delete them. Also inserts one audit row
  /// per leaf that actually changed, matching savePlatformSettings.js's own
  /// diff-and-log behavior (visible only in the web app — no audit-log
  /// screen exists here — but the two apps share one database/history).
  static Future<void> savePlatformSettings(PlatformSettings prev, PlatformSettings next) async {
    final row = await client.from("platform_settings").select("data").eq("id", "global").maybeSingle();
    final current = ((row?["data"] as Map?) ?? const {}).cast<String, dynamic>();
    final nextPatch = _platformSettingsTabPatch(next);
    final merged = {...current};
    for (final tab in nextPatch.keys) {
      final currentTab = ((current[tab] as Map?) ?? const {}).cast<String, dynamic>();
      merged[tab] = {...currentTab, ...nextPatch[tab]!};
    }

    final userId = currentUser?.id;
    await client.from("platform_settings").upsert({
      "id": "global",
      "data": merged,
      "updated_at": DateTime.now().toUtc().toIso8601String(),
      if (userId != null) "updated_by": userId,
    });

    final prevPatch = _platformSettingsTabPatch(prev);
    final auditRows = <Map<String, dynamic>>[];
    for (final tab in nextPatch.keys) {
      final prevTab = prevPatch[tab]!;
      final nextTab = nextPatch[tab]!;
      for (final key in nextTab.keys) {
        if (prevTab[key] != nextTab[key]) {
          auditRows.add({
            "changed_by": userId,
            "setting_key": "$tab.$key",
            "old_value": prevTab[key],
            "new_value": nextTab[key],
          });
        }
      }
    }
    if (auditRows.isNotEmpty) {
      await client.from("platform_settings_audit").insert(auditRows);
    }
  }

  static Map<String, dynamic> _productToJson(Product p) => {
        "id": p.id,
        "name": p.name,
        "priceCents": p.priceCents,
        "category": p.category,
        "archived": p.archived,
      };

  /// Shared by every jsonb-blob table write below (products, waiver_docs,
  /// membership_plans, programs_library, custom_meals, exercises). Real
  /// rows carry fields none of this app's models track at all — confirmed
  /// the hard way: a membership_plans row turned out to also hold `public`,
  /// `sharing`, `category`, `expiration`, `paymentType`, `stripePriceId`,
  /// `stripeProductId`, and more. A blind `{"id": id, "data": modeledJson}`
  /// upsert (this file's original approach for these 6 tables) would
  /// silently delete all of that — including the real Stripe linkage — the
  /// moment a coach edited any OTHER field through this app. Re-fetches
  /// fresh and merges the modeled patch on top instead, same as
  /// upsertClientRecordPatch/savePlatformSettings.
  static Future<void> _mergeJsonbUpsert(String table, String id, Map<String, dynamic> patch) async {
    final row = await client.from(table).select("data").eq("id", id).maybeSingle();
    final current = ((row?["data"] as Map?) ?? const {}).cast<String, dynamic>();
    await client.from(table).upsert({"id": id, "data": {...current, ...patch}});
  }

  static Future<void> upsertProduct(Product p) => _mergeJsonbUpsert("products", p.id, _productToJson(p));

  static Future<void> deleteProduct(String id) async {
    await client.from("products").delete().eq("id", id);
  }

  static Map<String, dynamic> _waiverDocToJson(WaiverDoc w) => {
        "id": w.id,
        "title": w.title,
        "body": w.body,
        "scope": w.scope,
        "planId": w.planId,
        "required": w.required,
        "archived": w.archived,
      };

  static Future<void> upsertWaiverDoc(WaiverDoc w) => _mergeJsonbUpsert("waiver_docs", w.id, _waiverDocToJson(w));

  static Future<void> deleteWaiverDoc(String id) async {
    await client.from("waiver_docs").delete().eq("id", id);
  }

  static Map<String, dynamic> _membershipPlanToJson(MembershipPlan p) => {
        "id": p.id,
        "name": p.name,
        "kind": p.kind.name,
        "maxSessions": p.maxSessions,
        "termMonths": p.termMonths,
        "allowedTypes": p.allowedTypes,
        "priceCents": p.priceCents,
        "archived": p.archived,
      };

  /// No delete counterpart — the app never hard-deletes a plan, only
  /// archives it (matches ManageMemberships.jsx's own UI, which has no
  /// delete action either).
  static Future<void> upsertMembershipPlan(MembershipPlan p) => _mergeJsonbUpsert("membership_plans", p.id, _membershipPlanToJson(p));

  static Map<String, dynamic> _savedProgramToJson(SavedProgram p) => {
        "id": p.id,
        "name": p.name,
        "type": "workout",
        "status": p.status,
        "createdBy": p.coachName,
        "programDays": p.programDays.map(_programDayToJson).toList(),
      };

  static Map<String, dynamic> _programDayToJson(ProgramDay d) => {
        "id": d.id,
        "title": d.title,
        "exercises": d.exercises.map(_exercisePrescriptionToJson).toList(),
      };

  static Map<String, dynamic> _exercisePrescriptionToJson(ExercisePrescription e) => {
        "id": e.id,
        "name": e.name,
        "exerciseId": e.exerciseId,
        "group": e.group,
        "sets": e.sets,
        "reps": e.reps,
        "weight": e.weight,
        "time": e.time,
        "distance": e.distance,
        "rest": e.rest,
        "notes": e.notes,
        "laterality": e.laterality,
        "supersetId": e.supersetId,
      };

  static Future<void> upsertProgramLibraryEntry(SavedProgram p) => _mergeJsonbUpsert("programs_library", p.id, _savedProgramToJson(p));

  static Future<void> deleteProgramLibraryEntry(String id) async {
    await client.from("programs_library").delete().eq("id", id);
  }

  static Map<String, dynamic> _mealDefToJson(MealDef m) => {
        "id": m.id,
        "name": m.name,
        "mealType": m.mealType,
        "calories": m.calories,
        "protein": m.protein,
        "carbs": m.carbs,
        "fats": m.fats,
        "ingredients": m.ingredients,
        "instructions": m.instructions,
        "dietTags": m.dietTags,
        "isCustom": m.isCustom,
      };

  static Future<void> insertCustomMeal(MealDef m) => _mergeJsonbUpsert("custom_meals", m.id, _mealDefToJson(m));

  static Map<String, dynamic> _exerciseDefToJson(ExerciseDef e) => {
        "id": e.id,
        "name": e.name,
        "movementPattern": e.movementPattern,
        "primaryMuscle": e.primaryMuscle,
        "equipmentIds": e.equipment,
        "setup": e.setup,
        "cues": e.cues,
        "coachNotes": e.coachNotes,
      };

  static Future<void> upsertExercise(ExerciseDef e) => _mergeJsonbUpsert("exercises", e.id, _exerciseDefToJson(e));

  static Future<void> deleteExercise(String id) async {
    await client.from("exercises").delete().eq("id", id);
  }

  /// `winner_mode`/`status`/`created_at` are all left to the table's own
  /// defaults ('auto', 'upcoming', '') — this app's Challenge model never
  /// models or reads any of the three, so there's nothing to send.
  static Future<void> insertChallenge(Challenge c, {required String createdBy}) async {
    final row = {
      "id": c.id,
      "template": c.template,
      "name": c.name,
      "description": c.description ?? "",
      "prize": c.prize ?? "",
      "metric": c.metric,
      "start_date": c.startDate,
      "end_date": c.endDate,
      "created_by": createdBy,
      "participants": c.participantIds,
    };
    await client.from("challenges").insert(row);
  }

  /// Covers both a client self-joining (appending their own id) and a coach
  /// picking a winner — the only two challenge mutations either role's UI
  /// actually performs.
  static Future<void> updateChallengeRow(String id, {List<String>? participantIds, String? winnerClientId}) async {
    final row = <String, dynamic>{
      if (participantIds != null) "participants": participantIds,
      if (winnerClientId != null) "winner": winnerClientId,
    };
    if (row.isEmpty) return;
    await client.from("challenges").update(row).eq("id", id);
  }

  static Future<void> deleteChallenge(String id) async {
    await client.from("challenges").delete().eq("id", id);
  }

  static Map<String, dynamic> _squadMemberMetaToJson(SquadMemberMeta m) => {
        "relationship": m.relationship,
        "status": m.status,
        "paymentEnabled": m.paymentEnabled,
        "minBalance": m.minBalance,
      };

  static Map<String, dynamic> _squadInviteToJson(SquadInvite i) => {
        "clientId": i.clientId,
        "sentAt": i.sentAt,
        "status": i.status,
      };

  static Map<String, dynamic> _squadActivityToJson(SquadActivityEntry a) => {
        "id": a.id,
        "type": a.type,
        "at": a.at,
        "actorName": a.actorName,
        "details": {"description": a.description},
      };

  static Future<void> insertSquad(Squad squad) async {
    final row = {
      "id": squad.id,
      "name": squad.name,
      "lead_id": squad.leadId,
      "member_ids": squad.memberIds,
      "member_meta": squad.memberMeta.map((k, v) => MapEntry(k, _squadMemberMetaToJson(v))),
      "max_size": squad.maxSize,
      "pending_invites": squad.pendingInvites.map(_squadInviteToJson).toList(),
      "activity": squad.activity.map(_squadActivityToJson).toList(),
    };
    await client.from("squads").insert(row);
  }

  /// Deletion is coach/owner-only (squads_delete_staff_only) — a client,
  /// including the Squad's own Lead, can never delete the row, so
  /// "Dissolve Squad" on the client side has to mean "log an activity
  /// entry" rather than an actual delete (matches the real schema's own
  /// documented intent). See deleteSquad below for the coach-side version.
  static Future<void> updateSquadRow(
    String id, {
    String? name,
    List<String>? memberIds,
    Map<String, SquadMemberMeta>? memberMeta,
    int? maxSize,
    List<SquadInvite>? pendingInvites,
    List<SquadActivityEntry>? activity,
  }) async {
    final row = <String, dynamic>{
      if (name != null) "name": name,
      if (memberIds != null) "member_ids": memberIds,
      if (memberMeta != null) "member_meta": memberMeta.map((k, v) => MapEntry(k, _squadMemberMetaToJson(v))),
      if (maxSize != null) "max_size": maxSize,
      if (pendingInvites != null) "pending_invites": pendingInvites.map(_squadInviteToJson).toList(),
      if (activity != null) "activity": activity.map(_squadActivityToJson).toList(),
    };
    if (row.isEmpty) return;
    await client.from("squads").update(row).eq("id", id);
  }

  static Future<void> deleteSquad(String id) async {
    await client.from("squads").delete().eq("id", id);
  }

  // ── Row mappers (snake_case DB -> the app's existing Dart models) ──

  /// Maps every row, but a single malformed row (unexpected null/shape in
  /// real, organically-grown test data) is skipped with a logged warning
  /// rather than aborting the whole list — the alternative is one bad
  /// row anywhere in ~50+ rows silently blanking the entire app back to
  /// mock data (see loadAndSeedCoreData's own outer catch).
  static List<T> _safeMap<T>(Iterable<dynamic> rows, T Function(Map<String, dynamic>) mapper) {
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(mapper((row as Map).cast<String, dynamic>()));
      } catch (e) {
        // ignore: avoid_print
        print("[SupabaseService] skipped malformed row: $e — $row");
      }
    }
    return out;
  }

  /// Real data isn't always as strongly typed as the schema intends — an
  /// ExercisePrescription's `sets`/`reps` inside a saved program have shown
  /// up as an empty-string placeholder rather than a number or null
  /// (confirmed against a real row, which `_safeMap` was silently dropping
  /// entirely because `as num?` throws — not returns null — on a String).
  /// A number casts directly; a string is parsed if it looks like one and
  /// treated as absent otherwise, falling through to the caller's `??`.
  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static ClientInfo _clientInfoFromRow(Map<String, dynamic> profile, Map<String, dynamic> c) {
    final plansRaw = (c["plans"] as List?) ?? const [];
    return ClientInfo(
      id: profile["id"] as String,
      name: (profile["name"] as String?) ?? "",
      email: profile["email"] as String?,
      phone: profile["phone"] as String?,
      photo: profile["photo_url"] as String?,
      city: c["city"] as String?,
      birthday: c["birthday"] as String?,
      membershipPlanId: c["membership_plan_id"] as String?,
      plans: _safeMap(
        plansRaw.whereType<Map>(),
        (p) => ClientPlanEnrollment(
          planId: p["planId"] as String? ?? "",
          status: p["status"] as String? ?? "active",
          startDate: p["startDate"] as String? ?? "",
          termMonths: _asInt(p["termMonths"]),
        ),
      ),
      membershipPaused: c["membership_paused"] as bool? ?? false,
      membershipPausedAt: c["membership_paused_at"] as String?,
      membershipFreezeEndsAt: c["membership_freeze_ends_at"] as String?,
      sessionCountOverride: _asInt(c["session_count_override"]),
      primaryTrainerId: c["primary_trainer_id"] as String?,
      hasOutstandingBalance: c["has_outstanding_balance"] as bool? ?? false,
    );
  }

  static Trainer _trainerFromRow(Map<String, dynamic> profile, Map<String, dynamic> t) {
    return Trainer(
      id: profile["id"] as String,
      name: (profile["name"] as String?) ?? "",
      photo: profile["photo_url"] as String?,
      phone: profile["phone"] as String?,
      email: profile["email"] as String?,
      availability: _availabilityFromJson(t["availability"]),
      commissionRate: (t["commission_rate"] as num?) ?? 0,
    );
  }

  static List<AvailabilityBlock> _availabilityFromJson(dynamic raw) {
    if (raw is! List) return const [];
    const dayNameToIndex = {"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6};
    final out = <AvailabilityBlock>[];
    for (final block in raw) {
      try {
        if (block is! Map) continue;
        final byDayRaw = (block["byDay"] as Map?) ?? const {};
        final byDay = <int, List<int>>{};
        byDayRaw.forEach((key, value) {
          final slots = (value as List?)?.whereType<num>().map((n) => n.toInt()).toList() ?? const <int>[];
          if (slots.isEmpty) return;
          final k = key.toString().toLowerCase();
          final weekday = int.tryParse(k) ?? dayNameToIndex[k.substring(0, k.length < 3 ? k.length : 3)];
          if (weekday != null) byDay[weekday] = slots;
        });
        out.add(AvailabilityBlock(
          sessionType: block["sessionType"] as String? ?? "",
          discipline: block["discipline"] as String? ?? "",
          byDay: byDay,
        ));
      } catch (e) {
        // ignore: avoid_print
        print("[SupabaseService] skipped malformed availability block: $e — $block");
      }
    }
    return out;
  }

  static Booking _bookingFromRow(Map<String, dynamic> row) {
    return Booking(
      id: row["id"] as String,
      clientId: row["client_id"] as String,
      trainerId: row["trainer_id"] as String,
      date: row["date"] as String,
      slot: _asInt(row["slot_min"]) ?? 0,
      sessionType: row["session_type"] as String? ?? "",
      discipline: row["discipline"] as String? ?? "",
      attendanceStatus: row["attendance_status"] as String?,
      locationName: _locationNameFrom(row["location"]),
      isPhysicalAssessment: row["is_physical_assessment"] as bool? ?? false,
    );
  }

  /// `bookings.location` is a JSON object (`{id, name, address, hint}`),
  /// not a plain string like this model's field name suggests — confirmed
  /// against real data. Handle a bare string too in case older rows (or a
  /// future schema change) ever store it that way.
  static String? _locationNameFrom(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Map) return raw["name"] as String?;
    return null;
  }

  static ClientRecord _clientRecordFromJson(String id, Map<String, dynamic> j) {
    // Defensive: this JSONB blob is the client's own free-form app state
    // (grew organically across ~20 schema phases), so every field is
    // optional here — an older or partially-populated record just falls
    // back to this model's own defaults for whatever isn't present.
    //
    // Confirmed against a real (near-empty) record: the top-level keys are
    // `program` (singular) and `logs` — NOT `savedPrograms`/`workoutLogs`
    // like this model's field names — plus `comms` and `tourSeen`. Every
    // real example seen so far had empty arrays for `program`/`logs`, so
    // their *item* shape (and therefore whether this model's
    // SavedProgram/WorkoutLogEntry field names are right) is still
    // unverified — re-check this mapping once a real client has an actual
    // assigned program or logged workout.
    final commsRaw = (j["comms"] as List?) ?? const [];
    final intakeRaw = (j["intake"] as Map?)?.cast<String, dynamic>() ?? const {};
    return ClientRecord(
      id: id,
      habits: ((j["habits"] as List?) ?? const []).whereType<String>().toList(),
      comms: _safeMap(
        commsRaw.whereType<Map>(),
        (m) => CommMessage(
          id: m["id"]?.toString() ?? "",
          who: m["who"] as String? ?? "client",
          text: m["text"] as String? ?? "",
          at: m["at"] as String? ?? "",
          trainerId: m["trainerId"] as String?,
          readByCoach: m["readByCoach"] as bool? ?? false,
        ),
      ),
      intake: intakeRaw.map((key, v) {
        final m = (v as Map).cast<String, dynamic>();
        return MapEntry(
          key,
          IntakeRecord(
            answers: (m["answers"] as Map?)?.cast<String, dynamic>() ?? const {},
            completed: m["completed"] as bool? ?? false,
            at: m["at"] as String?,
            by: m["by"] as String?,
          ),
        );
      }),
    );
  }

  static MembershipPlan _membershipPlanFromJson(Map<String, dynamic> j) {
    const kindByName = {"membership": PlanKind.membership, "package": PlanKind.package, "program": PlanKind.program};
    return MembershipPlan(
      id: j["id"] as String,
      name: j["name"] as String? ?? "",
      kind: kindByName[j["kind"] as String?] ?? PlanKind.package,
      maxSessions: _asInt(j["maxSessions"]),
      termMonths: _asInt(j["termMonths"]),
      allowedTypes: ((j["allowedTypes"] as List?) ?? const []).whereType<String>().toList(),
      priceCents: _asInt(j["priceCents"]) ?? 0,
      archived: j["archived"] as bool? ?? false,
    );
  }
}

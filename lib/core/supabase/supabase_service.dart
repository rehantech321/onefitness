import "package:supabase_flutter/supabase_flutter.dart";
import "../../data/models/availability_block.dart";
import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_plan.dart";
import "../../data/models/client_record.dart";
import "../../data/models/comm_message.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/trainer.dart";
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

  static int? _asInt(dynamic v) => (v as num?)?.toInt();

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

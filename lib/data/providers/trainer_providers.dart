import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/utils/date_utils.dart";
import "../mock/exercise_catalog.dart";
import "../mock/meal_catalog.dart";
import "../mock/mock_data.dart";
import "../models/blocked_time.dart";
import "../models/booking.dart";
import "../models/charge.dart";
import "../models/client_info.dart";
import "../models/client_record.dart";
import "../models/exercise_def.dart";
import "../models/meal_def.dart";
import "../models/nutrition_library_entry.dart";
import "../models/product.dart";
import "../models/saved_program.dart";
import "../models/waiver_doc.dart";

/// The signed-in coach/owner's auth value — null (signed out), "owner", or a
/// trainer id. Mirrors App.jsx's `trainerAuth`.
class TrainerAuthNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void signIn(String value) => state = value;
  void signOut() => state = null;
}

final trainerAuthProvider = NotifierProvider<TrainerAuthNotifier, String?>(TrainerAuthNotifier.new);

/// Every client at the gym (App.jsx `roster`, trainer-side view — a
/// superset of the client-side single-client providers).
class TrainerRosterNotifier extends Notifier<List<ClientInfo>> {
  @override
  List<ClientInfo> build() => MockData.trainerRoster();

  void update(String clientId, ClientInfo Function(ClientInfo) updater) =>
      state = state.map((c) => c.id == clientId ? updater(c) : c).toList();

  void remove(String clientId) => state = state.where((c) => c.id != clientId).toList();

  void setAll(List<ClientInfo> next) => state = next;
}

final trainerRosterProvider = NotifierProvider<TrainerRosterNotifier, List<ClientInfo>>(TrainerRosterNotifier.new);

/// clientId -> that client's day-to-day record (App.jsx `clientRecords`).
class TrainerClientRecordsNotifier extends Notifier<Map<String, ClientRecord>> {
  @override
  Map<String, ClientRecord> build() => MockData.trainerClientRecords();

  void update(String clientId, ClientRecord Function(ClientRecord) updater) =>
      state = {...state, clientId: updater(state[clientId]!)};

  void setAll(Map<String, ClientRecord> next) => state = next;
}

final trainerClientRecordsProvider =
    NotifierProvider<TrainerClientRecordsNotifier, Map<String, ClientRecord>>(TrainerClientRecordsNotifier.new);

/// All bookings across the whole roster (App.jsx `bookings`, trainer-side
/// view — a superset of the client-side `clientBookingsProvider`, which only
/// carries the signed-in client's own bookings).
class AllBookingsNotifier extends Notifier<List<Booking>> {
  @override
  List<Booking> build() => MockData.allBookings();

  void addBooking(Booking b) => state = [...state, b];

  void cancelBooking(String id) => state = state.where((b) => b.id != id).toList();

  void updateAttendance(String bookingId, String? status) =>
      state = state.map((b) => b.id == bookingId ? b.copyWith(attendanceStatus: status) : b).toList();

  void setAll(List<Booking> next) => state = next;
}

final allBookingsProvider = NotifierProvider<AllBookingsNotifier, List<Booking>>(AllBookingsNotifier.new);

/// Coach blocked-time-off entries (App.jsx blocked-time state) — starts
/// empty; no blocks exist in the mock seed data.
class BlockedTimesNotifier extends Notifier<List<BlockedTime>> {
  @override
  List<BlockedTime> build() => [];

  void add(BlockedTime b) => state = [...state, b];
  void remove(String id) => state = state.where((b) => b.id != id).toList();
  void setAll(List<BlockedTime> next) => state = next;
}

final blockedTimesProvider = NotifierProvider<BlockedTimesNotifier, List<BlockedTime>>(BlockedTimesNotifier.new);

/// The coach-editable exercise library (src/data/exercises.js), starting
/// from the curated seed catalog.
class ExerciseCatalogNotifier extends Notifier<List<ExerciseDef>> {
  @override
  List<ExerciseDef> build() => kExerciseCatalog;

  void upsert(ExerciseDef ex) {
    final exists = state.any((e) => e.id == ex.id);
    state = exists ? state.map((e) => e.id == ex.id ? ex : e).toList() : [...state, ex];
  }

  void remove(String id) => state = state.where((e) => e.id != id).toList();

  void setAll(List<ExerciseDef> next) => state = next;
}

final exerciseCatalogProvider = NotifierProvider<ExerciseCatalogNotifier, List<ExerciseDef>>(ExerciseCatalogNotifier.new);

/// The gym's charge ledger (Reports → Financial), coach-mutable for
/// waive/refund actions (mocked as local-only mutations, no real Stripe).
class ChargesNotifier extends Notifier<List<Charge>> {
  @override
  List<Charge> build() => MockData.charges();

  void remove(String id) => state = state.where((c) => c.id != id).toList();
  void waive(String id) => state = state.map((c) => c.id == id ? Charge(
        id: c.id, clientId: c.clientId, clientName: c.clientName, type: c.type, date: c.date, amount: c.amount,
        category: c.category, description: c.description, planId: c.planId, planName: c.planName,
        trainerId: c.trainerId, trainerName: c.trainerName, waivedAt: isoToday(),
      ) : c).toList();

  void setAll(List<Charge> next) => state = next;
}

final chargesProvider = NotifierProvider<ChargesNotifier, List<Charge>>(ChargesNotifier.new);

/// The built-in meal database (src/data/mealDatabase.js), read-only.
final mealCatalogProvider = Provider<List<MealDef>>((ref) => kMealCatalog);

/// Coach-authored custom meals, shared across every client's nutrition
/// builder once created (mirrors PlansArea.jsx's `customMeals` pool).
class CustomMealsNotifier extends Notifier<List<MealDef>> {
  @override
  List<MealDef> build() => [];

  void add(MealDef meal) => state = [...state, meal];

  void setAll(List<MealDef> next) => state = next;
}

final customMealsProvider = NotifierProvider<CustomMealsNotifier, List<MealDef>>(CustomMealsNotifier.new);

/// Reusable workout-program templates (ProgramsPanel.jsx's shared library).
class ProgramsLibraryNotifier extends Notifier<List<SavedProgram>> {
  @override
  List<SavedProgram> build() => [];

  void add(SavedProgram p) => state = [...state, p];
  void update(String id, SavedProgram Function(SavedProgram) updater) => state = state.map((p) => p.id == id ? updater(p) : p).toList();
  void remove(String id) => state = state.where((p) => p.id != id).toList();
  void setAll(List<SavedProgram> next) => state = next;
}

final programsLibraryProvider = NotifierProvider<ProgramsLibraryNotifier, List<SavedProgram>>(ProgramsLibraryNotifier.new);

/// Reusable nutrition-program templates (ProgramsPanel.jsx's shared library).
class NutritionLibraryNotifier extends Notifier<List<NutritionLibraryEntry>> {
  @override
  List<NutritionLibraryEntry> build() => [];

  void add(NutritionLibraryEntry e) => state = [...state, e];
  void remove(String id) => state = state.where((e) => e.id != id).toList();
}

final nutritionLibraryProvider = NotifierProvider<NutritionLibraryNotifier, List<NutritionLibraryEntry>>(NutritionLibraryNotifier.new);

/// Sellable fee-item catalog (ManageProducts.jsx).
class ProductsNotifier extends Notifier<List<Product>> {
  @override
  List<Product> build() => [];

  void upsert(Product p) {
    final exists = state.any((x) => x.id == p.id);
    state = exists ? state.map((x) => x.id == p.id ? p : x).toList() : [...state, p];
  }

  void remove(String id) => state = state.where((p) => p.id != id).toList();

  void setAll(List<Product> next) => state = next;
}

final productsProvider = NotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);

/// Waiver/contract documents (ManageWaivers.jsx).
class WaiversNotifier extends Notifier<List<WaiverDoc>> {
  @override
  List<WaiverDoc> build() => [
        const WaiverDoc(id: "signup-waiver", title: "General Liability Waiver", body: "I acknowledge the physical risks of exercise and release ONE Fitness from liability for injury arising from my participation."),
      ];

  void upsert(WaiverDoc w) {
    final exists = state.any((x) => x.id == w.id);
    state = exists ? state.map((x) => x.id == w.id ? w : x).toList() : [...state, w];
  }

  void remove(String id) => state = state.where((w) => w.id != id).toList();

  void setAll(List<WaiverDoc> next) => state = next;
}

final waiversProvider = NotifierProvider<WaiversNotifier, List<WaiverDoc>>(WaiversNotifier.new);

/// Which roster client is open in the Clients tab (App.jsx `activeId`).
class SelectedClientIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedClientIdProvider = NotifierProvider<SelectedClientIdNotifier, String?>(SelectedClientIdNotifier.new);

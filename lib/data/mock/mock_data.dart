import "../models/availability_block.dart";
import "../models/booking.dart";
import "../models/challenge.dart";
import "../models/charge.dart";
import "../models/client_info.dart";
import "../models/client_plan.dart";
import "../models/client_record.dart";
import "../models/comm_message.dart";
import "../models/exercise_prescription.dart";
import "../models/habit_log_entry.dart";
import "../models/measurement.dart";
import "../models/membership_plan.dart";
import "../models/nutrition_plan.dart";
import "../models/program_day.dart";
import "../models/roster_client.dart";
import "../models/saved_program.dart";
import "../models/signature.dart";
import "../models/trainer.dart";
import "../models/workout_log.dart";
import "../../core/utils/date_utils.dart";

/// Static demo data standing in for the Supabase-backed state in App.jsx,
/// scoped to the signed-in client "Alex Morgan" used to build out the
/// client-facing UI before backend wiring.
class MockData {
  MockData._();

  static const membershipPlans = <MembershipPlan>[
    MembershipPlan(
      id: "personalized-program",
      name: "Personalized Program",
      kind: PlanKind.program,
      maxSessions: 0,
      termMonths: 3,
      priceCents: 29900,
    ),
    MembershipPlan(
      id: "oneonone-package",
      name: "One-on-One Package",
      kind: PlanKind.package,
      maxSessions: 12,
      allowedTypes: ["one-on-one"],
      priceCents: 84000,
    ),
    MembershipPlan(
      id: "semiprivate-membership",
      name: "Semi-Private Membership",
      kind: PlanKind.membership,
      maxSessions: 12,
      allowedTypes: ["semi-private"],
      priceCents: 22900,
    ),
  ];

  static const trainers = <Trainer>[
    Trainer(
      id: "demo-marcus",
      name: "Marcus Rivera",
      phone: "18185550101",
      email: "marcus@onefitness.com",
      locationName: "ONE Fitness",
      locationAddress: "11300 Magnolia Blvd., North Hollywood, CA 91601",
      commissionRate: 20,
      availability: [
        AvailabilityBlock(
          sessionType: "semi-private",
          discipline: "personal-training",
          byDay: {
            1: [420, 480, 540, 600], // Mon 7/8/9/10am
            3: [420, 480, 540, 600], // Wed
            5: [420, 480, 540, 600], // Fri
          },
        ),
        AvailabilityBlock(
          sessionType: "semi-private",
          discipline: "boxing",
          byDay: {
            2: [600, 660], // Tue 10/11am
            4: [600, 660], // Thu
          },
        ),
      ],
    ),
  ];

  static MembershipPlan? planById(String? id) {
    if (id == null) return null;
    for (final p in membershipPlans) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String _plusDays(int n) {
    final d = DateTime.now().add(Duration(days: n));
    return isoDate(d);
  }

  static String _minusDays(int n) {
    final d = DateTime.now().subtract(Duration(days: n));
    return isoDate(d);
  }

  static const clientInfo = ClientInfo(
    id: "demo-alex",
    name: "Alex Morgan",
    email: "alex@example.com",
    phone: "18185559876",
    city: "North Hollywood",
    membershipPlanId: "semiprivate-membership",
    primaryTrainerId: "demo-marcus",
    plans: [
      ClientPlanEnrollment(planId: "semiprivate-membership", status: "active", startDate: "2026-06-01"),
    ],
  );

  static List<Booking> bookings() => [
        Booking(
          id: "bk-alex-1",
          clientId: "demo-alex",
          trainerId: "demo-marcus",
          date: _plusDays(2),
          slot: 540,
          sessionType: "semi-private",
          discipline: "personal-training",
          locationName: "ONE Fitness",
        ),
        Booking(
          id: "bk-alex-2",
          clientId: "demo-alex",
          trainerId: "demo-marcus",
          date: _plusDays(5),
          slot: 600,
          sessionType: "semi-private",
          discipline: "personal-training",
          locationName: "ONE Fitness",
        ),
        Booking(
          id: "bk-alex-3",
          clientId: "demo-alex",
          trainerId: "demo-marcus",
          date: _plusDays(9),
          slot: 540,
          sessionType: "semi-private",
          discipline: "boxing",
          locationName: "ONE Fitness",
        ),
        Booking(
          id: "bk-alex-0",
          clientId: "demo-alex",
          trainerId: "demo-marcus",
          date: _minusDays(4),
          slot: 540,
          sessionType: "semi-private",
          discipline: "personal-training",
          attendanceStatus: "checked-in",
          locationName: "ONE Fitness",
        ),
      ];

  static const _pushDay = ProgramDay(
    id: "day-push",
    title: "Push Day",
    exercises: [
      ExercisePrescription(
        id: "ex-p1",
        name: "Barbell Bench Press",
        group: "chest",
        sets: 4,
        reps: 8,
        weight: "135",
        rest: "120s",
        notes: "Retract scapula, feet flat. Control descent, drive through the floor.",
      ),
      ExercisePrescription(
        id: "ex-p2",
        name: "Overhead Press",
        group: "shoulders",
        sets: 3,
        reps: 10,
        weight: "65",
        rest: "90s",
        notes: "Brace core, squeeze glutes. Bar arcs slightly around the face.",
      ),
      ExercisePrescription(
        id: "ex-p3",
        name: "Tricep Rope Pushdown",
        group: "triceps",
        sets: 3,
        reps: 12,
        weight: "45",
        rest: "60s",
      ),
    ],
  );

  static const _pullDay = ProgramDay(
    id: "day-pull",
    title: "Pull Day",
    exercises: [
      ExercisePrescription(
        id: "ex-u1",
        name: "Deadlift",
        group: "back",
        sets: 4,
        reps: 6,
        weight: "185",
        rest: "120s",
        notes: "Hip hinge, bar against body. Hard brace before every rep.",
      ),
      ExercisePrescription(
        id: "ex-u2",
        name: "Pull-ups",
        group: "back",
        sets: 3,
        reps: 8,
        rest: "90s",
        notes: "Full dead hang to chin over bar.",
      ),
      ExercisePrescription(
        id: "ex-u3",
        name: "Dumbbell Curl",
        group: "biceps",
        sets: 3,
        reps: 12,
        weight: "30",
        rest: "60s",
        laterality: "unilateral",
      ),
    ],
  );

  static const savedPrograms = <SavedProgram>[
    SavedProgram(
      id: "prog-alex-ppl",
      name: "Push / Pull",
      coachName: "Marcus Rivera",
      programDays: [_pushDay, _pullDay],
    ),
  ];

  static List<WorkoutLogEntry> workoutLogs() => [
        WorkoutLogEntry(
          id: "wl1",
          date: _minusDays(4),
          programId: "prog-alex-ppl",
          programName: "Push / Pull",
          dayId: "day-push",
          dayTitle: "Push Day",
          loggedAt: "${_minusDays(4)}T18:30:00",
          exercises: const [
            LoggedExercise(name: "Barbell Bench Press", sets: [
              LoggedSet(setNum: 1, targetReps: 8, completedReps: 8, completedWeight: 130, completed: true),
              LoggedSet(setNum: 2, targetReps: 8, completedReps: 8, completedWeight: 130, completed: true),
              LoggedSet(setNum: 3, targetReps: 8, completedReps: 7, completedWeight: 135, completed: true),
              LoggedSet(setNum: 4, targetReps: 8, completedReps: 6, completedWeight: 135, completed: true),
            ]),
            LoggedExercise(name: "Overhead Press", sets: [
              LoggedSet(setNum: 1, targetReps: 10, completedReps: 10, completedWeight: 60, completed: true),
              LoggedSet(setNum: 2, targetReps: 10, completedReps: 9, completedWeight: 65, completed: true),
              LoggedSet(setNum: 3, targetReps: 10, completedReps: 8, completedWeight: 65, completed: true),
            ]),
          ],
        ),
      ];

  static const _nutritionPlan = NutritionPlan(
    trainingTargets: MacroTargets(calories: "2500", protein: "30", carbs: "45", fats: "25", water: "128"),
    restTargets: MacroTargets(calories: "2000", protein: "35", carbs: "35", fats: "30", water: "96"),
    mealBudgets: {"breakfast": "550", "lunch": "700", "dinner": "750", "snacks": "300", "smoothies": "200"},
    breakfast: [
      NutritionMeal(
        id: "meal-b1",
        name: "Eggs & Oatmeal",
        calories: 540,
        protein: 33,
        carbs: 56,
        fats: 15,
        ingredients: [
          Ingredient(item: "Whole eggs", qty: 3, unit: "large"),
          Ingredient(item: "Egg whites", qty: 2, unit: "large"),
          Ingredient(item: "Rolled oats", qty: 1, unit: "cup"),
          Ingredient(item: "Blueberries", qty: 0.5, unit: "cup"),
          Ingredient(item: "Honey", qty: 1, unit: "tbsp"),
        ],
        notes: "Cook oats in water or almond milk. Scramble eggs. Top with berries and honey.",
      ),
    ],
    lunch: [
      NutritionMeal(
        id: "meal-l1",
        name: "Grilled Chicken & Rice Bowl",
        calories: 680,
        protein: 52,
        carbs: 74,
        fats: 14,
        ingredients: [
          Ingredient(item: "Chicken breast", qty: 6, unit: "oz"),
          Ingredient(item: "White rice", qty: 1, unit: "cup"),
          Ingredient(item: "Broccoli", qty: 1.5, unit: "cup"),
          Ingredient(item: "Olive oil", qty: 1, unit: "tbsp"),
        ],
        notes: "Season chicken with garlic, salt & pepper. Grill or bake at 400°F. Steam broccoli.",
      ),
    ],
    dinner: [
      NutritionMeal(
        id: "meal-d1",
        name: "Salmon with Sweet Potato & Asparagus",
        calories: 710,
        protein: 48,
        carbs: 52,
        fats: 28,
        ingredients: [
          Ingredient(item: "Atlantic salmon fillet", qty: 6, unit: "oz"),
          Ingredient(item: "Sweet potato", qty: 1, unit: "medium"),
          Ingredient(item: "Asparagus", qty: 1, unit: "cup"),
          Ingredient(item: "Olive oil", qty: 1.5, unit: "tbsp"),
        ],
        notes: "Bake salmon at 400°F for 12–15 min. Roast sweet potato 25 min, asparagus last 10 min.",
      ),
    ],
    snacks: [
      NutritionMeal(
        id: "meal-s1",
        name: "Greek Yogurt & Almonds",
        calories: 185,
        protein: 18,
        carbs: 14,
        fats: 7,
        ingredients: [
          Ingredient(item: "Non-fat Greek yogurt", qty: 1, unit: "cup"),
          Ingredient(item: "Raw almonds", qty: 10, unit: "g"),
        ],
      ),
      NutritionMeal(
        id: "meal-s2",
        name: "Apple & Peanut Butter",
        calories: 115,
        protein: 4,
        carbs: 18,
        fats: 4,
        ingredients: [
          Ingredient(item: "Apple", qty: 1, unit: "medium"),
          Ingredient(item: "Natural peanut butter", qty: 1, unit: "tbsp"),
        ],
      ),
    ],
    smoothies: [
      NutritionMeal(
        id: "meal-sm1",
        name: "Morning Recovery Protein Shake",
        calories: 150,
        protein: 28,
        carbs: 8,
        fats: 2,
        ingredients: [
          Ingredient(item: "Whey protein powder", qty: 1, unit: "scoop"),
          Ingredient(item: "Unsweetened almond milk", qty: 1, unit: "cup"),
          Ingredient(item: "Frozen banana", qty: 0.5, unit: "medium"),
        ],
        notes: "Blend 45 seconds. Best within 30 min of training.",
      ),
    ],
    guidelines: "TRAINING DAYS (2,500 kcal · 30P / 45C / 25F): Eat around your workout. Have a solid "
        "carb + protein meal in the 90 min before training, and refuel with protein + carbs within an "
        "hour after.\n\n"
        "REST DAYS (2,000 kcal · 35P / 35C / 30F): Calories and carbs come down since you're not "
        "training. Protein goes UP as a percentage to protect muscle.\n\n"
        "HYDRATION: 128 oz (1 gallon) on training days, ~96 oz on rest days.\n\n"
        "WEEKLY CHECK-IN: Weigh in 3× per week, first thing in the morning, and log it. We adjust off "
        "the weekly average, never a single day.",
  );

  static ClientRecord clientRecord() => ClientRecord(
        id: "demo-alex",
        loggedDates: [_minusDays(4), _minusDays(11)],
        habits: const ["water", "steps", "sleep"],
        habitLogByDate: {
          isoToday(): const HabitLogEntry(checked: {"water": true, "steps": false, "sleep": true}, energy: 7, motivation: 8),
          _minusDays(1): const HabitLogEntry(checked: {"water": true, "steps": true, "sleep": true}, energy: 8, motivation: 8),
        },
        measurements: [
          Measurement(id: "m1", date: _minusDays(56), weight: "182", bodyfat: "22", chest: "40", waist: "34", hips: "40", arms: "14", thighs: "23"),
          Measurement(id: "m2", date: _minusDays(28), weight: "178", bodyfat: "20.5", chest: "40.5", waist: "33", hips: "39.5", arms: "14.2", thighs: "22.8"),
          Measurement(id: "m3", date: _minusDays(4), weight: "175", bodyfat: "19", chest: "41", waist: "32", hips: "39", arms: "14.5", thighs: "22.5"),
        ],
        savedPrograms: savedPrograms,
        workoutLogs: workoutLogs(),
        signatures: [
          SignedDocument(
            id: "sig-waiver",
            title: "Liability Waiver & Release",
            signedAt: "Jun 1, 2026",
            summary: "Standard ONE Fitness liability waiver, signed at membership start.",
          ),
        ],
        nutrition: _nutritionPlan,
        comms: [
          CommMessage(
            id: "c2",
            who: "trainer",
            text: "You're crushing it Alex — let's push a little heavier next week.",
            at: stamp(DateTime.now().subtract(const Duration(days: 1))),
            trainerId: "demo-marcus",
          ),
          CommMessage(
            id: "c1",
            who: "client",
            text: "Loving the new program! Felt strong today.",
            at: stamp(DateTime.now().subtract(const Duration(days: 1, hours: 1))),
            trainerId: "demo-marcus",
            readByCoach: true,
          ),
        ],
        challengeProgress: {
          "ch-squat-pr": const [
            ChallengeProgressEntry(value: 135, loggedAt: "Jul 20, 5:30 PM"),
            ChallengeProgressEntry(value: 145, loggedAt: "Jul 25, 6:10 PM"),
          ],
        },
      );

  static List<Challenge> challenges() => [
        Challenge(
          id: "ch-squat-pr",
          name: "Squat PR Challenge",
          template: "progressive-overload",
          metric: "Strength gain (lbs)",
          startDate: _minusDays(5),
          endDate: _plusDays(25),
          description: "Biggest squat improvement wins. Log your heaviest set.",
          prize: "ONE Fitness hoodie",
          participantIds: const ["demo-alex"],
          otherLeaderboard: const [
            LeaderboardEntry(clientId: "demo-ava", name: "Ava Ramirez", score: 150),
            LeaderboardEntry(clientId: "demo-liam", name: "Liam Park", score: 120),
            LeaderboardEntry(clientId: "demo-sofia", name: "Sofia Nguyen", score: 100),
          ],
        ),
        Challenge(
          id: "ch-attendance",
          name: "August Attendance Showdown",
          template: "attendance",
          metric: "Sessions attended",
          startDate: _plusDays(3),
          endDate: _plusDays(33),
          description: "Show up the most this month. Every checked-in session counts.",
          prize: "Free month of membership",
          participantIds: const [],
          otherLeaderboard: const [],
        ),
      ];

  /// Other clients at the gym, invitable to a Squad via member search — not
  /// full accounts, just enough to search/display/invite.
  static const roster = <RosterClient>[
    RosterClient(id: "demo-jordan", name: "Jordan Casey", email: "jordan@example.com", phone: "18185558765"),
    RosterClient(id: "demo-taylor", name: "Taylor Brooks", email: "taylor@example.com", phone: "18185557654"),
  ];

  // ── Trainer/coach-side mock data ──────────────────────────────────────
  // A broader roster (Alex + Jordan + Taylor) so the coach dashboard, client
  // list, and schedule have more than one person to show. Jordan and Taylor
  // are deliberately left with gaps (no nutrition program / no program at
  // all, an unlogged past session) so the "Needs Attention" list on the
  // coach dashboard has real, non-empty content to demonstrate.

  static const jordanInfo = ClientInfo(
    id: "demo-jordan",
    name: "Jordan Casey",
    email: "jordan@example.com",
    phone: "18185558765",
    city: "North Hollywood",
    membershipPlanId: "oneonone-package",
    primaryTrainerId: "demo-marcus",
    plans: [ClientPlanEnrollment(planId: "oneonone-package", status: "active", startDate: "2026-06-01")],
  );

  static const taylorInfo = ClientInfo(
    id: "demo-taylor",
    name: "Taylor Brooks",
    email: "taylor@example.com",
    phone: "18185557654",
    city: "North Hollywood",
    membershipPlanId: "oneonone-package",
    primaryTrainerId: "demo-marcus",
    plans: [ClientPlanEnrollment(planId: "oneonone-package", status: "active", startDate: "2026-06-01")],
  );

  static List<ClientInfo> trainerRoster() => [clientInfo, jordanInfo, taylorInfo];

  static const _jordanProgram = SavedProgram(
    id: "prog-jordan-strength",
    name: "Full Body Strength",
    coachName: "Marcus Rivera",
    programDays: [
      ProgramDay(id: "day-jordan-1", title: "Full Body A", exercises: [
        ExercisePrescription(id: "ex-j1", name: "Barbell Back Squat", group: "quads", sets: 4, reps: 6, weight: "185", rest: "120s"),
        ExercisePrescription(id: "ex-j2", name: "Bench Press", group: "chest", sets: 4, reps: 8, weight: "115", rest: "90s"),
      ]),
    ],
  );

  static ClientRecord jordanRecord() => ClientRecord(
        id: "demo-jordan",
        loggedDates: [_minusDays(10)],
        savedPrograms: const [_jordanProgram],
        // No savedNutritionPrograms / nutrition — triggers "No nutrition program".
      );

  static ClientRecord taylorRecord() => const ClientRecord(
        id: "demo-taylor",
        // No savedPrograms and no nutrition — triggers both "No workout
        // program" and "No nutrition program" (matches her One-on-One
        // package, which is coach-managed session-only, by design).
      );

  static Map<String, ClientRecord> trainerClientRecords() => {
        "demo-alex": clientRecord(),
        "demo-jordan": jordanRecord(),
        "demo-taylor": taylorRecord(),
      };

  /// All bookings across the whole roster (Alex + Jordan + Taylor), for the
  /// coach dashboard/schedule — a superset of the client-side
  /// [bookings], which only carries Alex's.
  static List<Booking> allBookings() => [
        ...bookings(),
        Booking(
          id: "bk-jordan-today",
          clientId: "demo-jordan",
          trainerId: "demo-marcus",
          date: isoToday(),
          slot: 480,
          sessionType: "one-on-one",
          discipline: "personal-training",
          locationName: "ONE Fitness",
          // Already past earlier today and never marked — surfaces under
          // "No attendance logged".
        ),
        Booking(
          id: "bk-jordan-future",
          clientId: "demo-jordan",
          trainerId: "demo-marcus",
          date: _plusDays(3),
          slot: 540,
          sessionType: "one-on-one",
          discipline: "personal-training",
          locationName: "ONE Fitness",
        ),
        Booking(
          id: "bk-taylor-yesterday",
          clientId: "demo-taylor",
          trainerId: "demo-marcus",
          date: _minusDays(1),
          slot: 600,
          sessionType: "one-on-one",
          discipline: "personal-training",
          locationName: "ONE Fitness",
          // Unlogged past session — also surfaces under "No attendance logged".
        ),
        Booking(
          id: "bk-taylor-today",
          clientId: "demo-taylor",
          trainerId: "demo-marcus",
          date: isoToday(),
          slot: 660,
          sessionType: "one-on-one",
          discipline: "boxing",
          locationName: "ONE Fitness",
        ),
      ];

  static List<Charge> charges() => [
        Charge(
          id: "chg-alex-1",
          clientId: "demo-alex",
          clientName: "Alex Morgan",
          type: "purchase",
          date: _minusDays(20),
          amount: 229.0,
          category: "Membership",
          description: "Semi-Private Membership — monthly",
          planId: "semiprivate-membership",
          planName: "Semi-Private Membership",
          trainerId: "demo-marcus",
          trainerName: "Marcus Rivera",
        ),
        Charge(
          id: "chg-jordan-1",
          clientId: "demo-jordan",
          clientName: "Jordan Casey",
          type: "purchase",
          date: _minusDays(15),
          amount: 840.0,
          category: "Package",
          description: "One-on-One Package — 12 sessions",
          planId: "oneonone-package",
          planName: "One-on-One Package",
          trainerId: "demo-marcus",
          trainerName: "Marcus Rivera",
        ),
        Charge(
          id: "chg-taylor-1",
          clientId: "demo-taylor",
          clientName: "Taylor Brooks",
          type: "purchase",
          date: _minusDays(9),
          amount: 840.0,
          category: "Package",
          description: "One-on-One Package — 12 sessions",
          planId: "oneonone-package",
          planName: "One-on-One Package",
          trainerId: "demo-marcus",
          trainerName: "Marcus Rivera",
        ),
        Charge(
          id: "chg-alex-2",
          clientId: "demo-alex",
          clientName: "Alex Morgan",
          type: "early_termination_fee",
          date: _minusDays(2),
          amount: 50.0,
          category: "Fee",
          description: "Early termination fee",
          trainerId: "demo-marcus",
          trainerName: "Marcus Rivera",
        ),
      ];
}

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/nutrition_helpers.dart";
import "package:onefitness/data/models/nutrition_plan.dart";
import "package:onefitness/features/client/plans/meal_ingredient_editor.dart";

/// Clients can change how much of each ingredient is in a meal they picked,
/// and the calories and macros have to follow. The numbers must come out the
/// same whoever did the editing and whenever they are read back, so these
/// tests pin all three places the figure can diverge: the recalculation
/// itself, what the editor hands back, and what survives a save/reload.
void main() {
  // Macros are per ONE unit of the ingredient — here, per gram.
  const oats = Ingredient(
    item: "Rolled oats",
    qty: 100,
    unit: "g",
    category: "pantry",
    macros: IngredientMacros(cals: 3.8, p: 0.13, c: 0.68, f: 0.07),
  );
  const whey = Ingredient(
    item: "Whey protein",
    qty: 30,
    unit: "g",
    category: "pantry",
    macros: IngredientMacros(cals: 4, p: 0.8, c: 0.04, f: 0.03),
  );

  NutritionMeal mealWith({
    List<Ingredient> ingredients = const [oats, whey],
    Map<int, String> overrides = const {},
    MacroSnapshot? scaledMacros,
  }) => NutritionMeal(
    id: "m1",
    name: "Overnight oats",
    calories: 500,
    protein: 37,
    carbs: 69.2,
    fats: 7.9,
    ingredients: ingredients,
    scaledMacros: scaledMacros,
    overrides: overrides,
  );

  group("macros recompute from the ingredient amounts", () {
    test("an untouched meal totals its own ingredients", () {
      final m = effectiveMacros(mealWith());
      expect(m.calories, 500); // 100g oats @3.8 + 30g whey @4
      expect(m.protein, 37);
      expect(m.carbs, 69.2);
      expect(m.fats, 7.9);
    });

    test("raising one ingredient raises only that ingredient's share", () {
      // Oats 100g -> 150g: +190 kcal, +6.5g protein. Whey is untouched.
      final m = effectiveMacros(mealWith(overrides: {0: "150"}));
      expect(m.calories, 690);
      expect(m.protein, 43.5);
      expect(m.carbs, 103.2);
      expect(m.fats, 11.4);
    });

    test("lowering an ingredient lowers the totals", () {
      final m = effectiveMacros(mealWith(overrides: {1: "15"}));
      expect(m.calories, 440); // 380 + 60
      expect(m.protein, 25); // 13 + 12
    });

    test("dropping an ingredient to zero removes it from the totals", () {
      final m = effectiveMacros(mealWith(overrides: {1: "0"}));
      expect(m.calories, 380);
      expect(m.protein, 13);
    });

    test("decimal amounts are honoured, not truncated", () {
      final m = effectiveMacros(mealWith(overrides: {0: "12.5"}));
      expect(m.calories, 168); // 47.5 + 120, rounded
    });

    test("clearing the overrides restores the original meal exactly", () {
      final edited = mealWith(overrides: {0: "150", 1: "60"});
      final reset = edited.copyWith(clearOverrides: true);
      expect(effectiveMacros(reset).calories, 500);
      expect(effectiveIngredients(reset).map((i) => i.qty), [100, 30]);
    });

    test("the ingredient list shown reflects the edit", () {
      final ings = effectiveIngredients(mealWith(overrides: {0: "150"}));
      expect(ings[0].qty, 150);
      expect(ings[0].item, "Rolled oats"); // name and unit are not disturbed
      expect(ings[0].unit, "g");
      expect(ings[1].qty, 30);
    });

    test("an unparseable override falls back to the original amount", () {
      // The editor refuses to store anything it can't parse, but older data
      // might. Such an entry leaves that ingredient at its recipe amount
      // instead of dropping it, so the meal still adds up to something real
      // rather than quietly losing a third of its calories.
      final m = effectiveMacros(mealWith(overrides: {0: "lots"}));
      expect(m.calories, 500);
      expect(effectiveIngredients(mealWith(overrides: {0: "lots"})).first.qty, 100);
    });
  });

  group("meals whose ingredients carry no nutrition data", () {
    // Legacy and hand-typed meals have no per-ingredient macros, so there is
    // nothing to add up. Rather than show zeroes, the stored totals are
    // adjusted in proportion — approximate, and the editor says so.
    const plain = [
      Ingredient(item: "Chicken", qty: 100, unit: "g"),
      Ingredient(item: "Rice", qty: 100, unit: "g"),
    ];
    const stored = MacroSnapshot(calories: 500, protein: 40, carbs: 60, fats: 10);

    test("there is nothing to recompute from", () {
      expect(computeMacrosFromIngredients(plain), isNull);
    });

    test("totals scale with the total amount of food", () {
      final m = effectiveMacros(
        mealWith(ingredients: plain, scaledMacros: stored, overrides: {0: "150"}),
      );
      expect(m.calories, 625); // 250g of 200g = 1.25x
      expect(m.protein, 50);
    });

    test("an untouched meal keeps its stored totals untouched", () {
      final m = effectiveMacros(mealWith(ingredients: plain, scaledMacros: stored));
      expect(m.calories, 500);
    });
  });

  group("an edit survives being saved and read back", () {
    // The override map is written with string keys (JSON has no integer
    // keys) and the per-unit macros go with it, so the figures after a
    // reload are the same ones the client saw while editing.
    test("overrides and macro data both round-trip", () {
      final edited = mealWith(overrides: {0: "150"});

      final asJson = {
        "overrides": edited.overrides.map((k, v) => MapEntry(k.toString(), v)),
        "ingredients": edited.ingredients.map((i) => i.toJson()).toList(),
      };

      final backIngredients = (asJson["ingredients"] as List)
          .map((j) => Ingredient.fromJson((j as Map).cast<String, dynamic>()))
          .toList();
      final backOverrides = (asJson["overrides"] as Map)
          .map((k, v) => MapEntry(int.parse(k.toString()), v.toString()));

      expect(backIngredients.first.macros, isNotNull,
          reason: "per-unit macros must persist or totals change after reload");

      final reloaded = mealWith(ingredients: backIngredients, overrides: backOverrides);
      expect(effectiveMacros(reloaded).calories, effectiveMacros(edited).calories);
      expect(effectiveMacros(reloaded).protein, 43.5);
    });
  });

  group("the editor sheet", () {
    Future<NutritionMeal?> open(WidgetTester tester, NutritionMeal meal, {int? budget}) async {
      NutritionMeal? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showMealIngredientEditor(ctx, meal: meal, budget: budget),
              child: const Text("open"),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets("opens showing the meal's current totals", (tester) async {
      await open(tester, mealWith());
      expect(find.text("Overnight oats"), findsOneWidget);
      expect(find.text("500 kcal"), findsOneWidget);
      expect(find.text("Rolled oats"), findsOneWidget);
    });

    testWidgets("typing a new amount updates the calories as you go", (tester) async {
      await open(tester, mealWith());
      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      expect(find.text("690 kcal"), findsOneWidget);
      expect(find.text("Protein 43.5g · Carbs 103.2g · Fat 11.4g"), findsOneWidget);
    });

    testWidgets("a half-typed number does not flash the totals to zero", (tester) async {
      await open(tester, mealWith());
      await tester.enterText(find.byType(TextField).first, "");
      await tester.pump();
      expect(find.text("0 kcal"), findsNothing);
      expect(find.text("500 kcal"), findsOneWidget);
    });

    testWidgets("changed ingredients are marked, unchanged ones are not", (tester) async {
      await open(tester, mealWith());
      expect(find.text("changed"), findsNothing);
      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      expect(find.text("changed"), findsOneWidget);
    });

    testWidgets("typing the original amount back clears the edit", (tester) async {
      await open(tester, mealWith());
      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, "100");
      await tester.pump();
      expect(find.text("changed"), findsNothing);
      expect(find.text("500 kcal"), findsOneWidget);
    });

    testWidgets("Reset appears only after a change, and undoes it", (tester) async {
      await open(tester, mealWith());
      expect(find.text("Reset"), findsNothing);

      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      expect(find.text("Reset"), findsOneWidget);

      await tester.tap(find.text("Reset"));
      await tester.pump();
      expect(find.text("500 kcal"), findsOneWidget);
      expect(find.text("changed"), findsNothing);
    });

    testWidgets("saving returns the meal carrying the edit", (tester) async {
      NutritionMeal? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  saved = await showMealIngredientEditor(ctx, meal: mealWith()),
              child: const Text("open"),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      await tester.tap(find.text("Save changes"));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.overrides, {0: "150"});
      expect(effectiveMacros(saved!).calories, 690);
      // The recipe itself is untouched, so Reset can always get back to it.
      expect(saved!.ingredients.first.qty, 100);
    });

    testWidgets("closing without saving returns nothing", (tester) async {
      NutritionMeal? saved;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                saved = await showMealIngredientEditor(ctx, meal: mealWith());
                closed = true;
              },
              child: const Text("open"),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(saved, isNull);
    });

    testWidgets("going well over the meal's budget is flagged, not blocked", (tester) async {
      await open(tester, mealWith(), budget: 500);
      expect(find.textContaining("Over this meal's calorie budget"), findsNothing);

      await tester.enterText(find.byType(TextField).first, "150");
      await tester.pump();
      expect(find.textContaining("Over this meal's calorie budget"), findsOneWidget);
      // Still saveable — the client's day is theirs to balance.
      expect(find.text("Save changes"), findsOneWidget);
    });

    testWidgets("meals without nutrition data say the totals are approximate", (tester) async {
      await open(
        tester,
        mealWith(
          ingredients: const [
            Ingredient(item: "Chicken", qty: 100, unit: "g"),
            Ingredient(item: "Rice", qty: 100, unit: "g"),
          ],
          scaledMacros: const MacroSnapshot(calories: 500, protein: 40, carbs: 60, fats: 10),
        ),
      );
      expect(find.textContaining("don't carry nutrition data"), findsOneWidget);
    });
  });
}

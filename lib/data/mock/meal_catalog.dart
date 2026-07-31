import "../models/meal_def.dart";

/// A curated slice of the full meal database (src/data/mealDatabase.js
/// ships 135 built-in meals) — enough for the nutrition builder's meal
/// picker to feel real without hand-porting the entire seed file.
const kMealCatalog = <MealDef>[
  MealDef(id: "meal-oats-berries", name: "Oatmeal with Berries & Almond Butter", mealType: "breakfast", calories: 420, protein: 16, carbs: 58, fats: 14, ingredients: ["1 cup oats", "1/2 cup mixed berries", "1 tbsp almond butter"], dietTags: ["Vegetarian", "Quick"]),
  MealDef(id: "meal-egg-white-veggie", name: "Egg White & Veggie Scramble", mealType: "breakfast", calories: 320, protein: 30, carbs: 18, fats: 12, ingredients: ["6 egg whites", "1 cup spinach", "1/2 cup bell pepper"], dietTags: ["High Protein", "Low Carb"]),
  MealDef(id: "meal-greek-yogurt-bowl", name: "Greek Yogurt Protein Bowl", mealType: "breakfast", calories: 340, protein: 32, carbs: 34, fats: 8, ingredients: ["1 cup Greek yogurt", "1/2 cup granola", "1 tbsp honey"], dietTags: ["High Protein", "Vegetarian"]),
  MealDef(id: "meal-protein-pancakes", name: "Protein Pancakes", mealType: "breakfast", calories: 380, protein: 28, carbs: 44, fats: 9, ingredients: ["1 scoop protein powder", "2 eggs", "1/2 banana"], dietTags: ["High Protein"]),
  MealDef(id: "meal-avocado-toast", name: "Avocado Toast with Eggs", mealType: "breakfast", calories: 400, protein: 18, carbs: 32, fats: 22, ingredients: ["2 slices whole grain bread", "1/2 avocado", "2 eggs"], dietTags: ["Vegetarian", "Quick"]),
  MealDef(id: "meal-chicken-rice-bowl", name: "Grilled Chicken & Rice Bowl", mealType: "lunch", calories: 520, protein: 42, carbs: 55, fats: 12, ingredients: ["6 oz chicken breast", "1 cup rice", "1 cup broccoli"], dietTags: ["High Protein", "Meal Prep"]),
  MealDef(id: "meal-turkey-wrap", name: "Turkey & Hummus Wrap", mealType: "lunch", calories: 450, protein: 30, carbs: 40, fats: 16, ingredients: ["Whole wheat wrap", "4 oz turkey", "2 tbsp hummus"], dietTags: ["Quick"]),
  MealDef(id: "meal-tuna-salad", name: "Tuna & White Bean Salad", mealType: "lunch", calories: 380, protein: 34, carbs: 28, fats: 12, ingredients: ["1 can tuna", "1/2 cup white beans", "mixed greens"], dietTags: ["High Protein", "Low Carb"]),
  MealDef(id: "meal-buddha-bowl", name: "Quinoa Buddha Bowl", mealType: "lunch", calories: 460, protein: 18, carbs: 62, fats: 16, ingredients: ["1 cup quinoa", "roasted vegetables", "tahini dressing"], dietTags: ["Vegan", "Meal Prep"]),
  MealDef(id: "meal-chicken-wrap", name: "Chicken Caesar Wrap", mealType: "lunch", calories: 480, protein: 36, carbs: 38, fats: 18, ingredients: ["Whole wheat wrap", "5 oz chicken", "romaine", "caesar dressing"], dietTags: ["High Protein"]),
  MealDef(id: "meal-salmon-veg", name: "Baked Salmon with Roasted Vegetables", mealType: "dinner", calories: 540, protein: 40, carbs: 30, fats: 24, ingredients: ["6 oz salmon", "1 cup mixed vegetables", "1 tbsp olive oil"], dietTags: ["High Protein", "Low Carb"]),
  MealDef(id: "meal-steak-potato", name: "Grilled Steak with Sweet Potato", mealType: "dinner", calories: 580, protein: 45, carbs: 48, fats: 20, ingredients: ["6 oz sirloin steak", "1 medium sweet potato", "asparagus"], dietTags: ["High Protein"]),
  MealDef(id: "meal-turkey-chili", name: "Turkey Chili", mealType: "dinner", calories: 420, protein: 36, carbs: 38, fats: 12, ingredients: ["1 lb ground turkey", "kidney beans", "diced tomatoes"], dietTags: ["High Protein", "Meal Prep"]),
  MealDef(id: "meal-shrimp-stirfry", name: "Shrimp Stir-Fry", mealType: "dinner", calories: 440, protein: 34, carbs: 42, fats: 14, ingredients: ["6 oz shrimp", "mixed stir-fry vegetables", "1 cup rice"], dietTags: ["Low Carb"]),
  MealDef(id: "meal-veggie-pasta", name: "Veggie Whole Wheat Pasta", mealType: "dinner", calories: 460, protein: 18, carbs: 68, fats: 12, ingredients: ["Whole wheat pasta", "marinara", "zucchini", "mushrooms"], dietTags: ["Vegetarian"]),
  MealDef(id: "meal-almonds", name: "Almonds & Apple", mealType: "snacks", calories: 220, protein: 6, carbs: 24, fats: 12, ingredients: ["1 oz almonds", "1 medium apple"], dietTags: ["Quick", "Vegan"]),
  MealDef(id: "meal-protein-bar", name: "Protein Bar", mealType: "snacks", calories: 200, protein: 20, carbs: 22, fats: 7, ingredients: ["1 protein bar"], dietTags: ["Quick", "High Protein"]),
  MealDef(id: "meal-cottage-cheese-pineapple", name: "Cottage Cheese & Pineapple", mealType: "snacks", calories: 180, protein: 22, carbs: 16, fats: 3, ingredients: ["1 cup cottage cheese", "1/2 cup pineapple"], dietTags: ["High Protein", "Vegetarian"]),
  MealDef(id: "meal-hardboiled-eggs", name: "Hard-Boiled Eggs & Carrots", mealType: "snacks", calories: 160, protein: 14, carbs: 10, fats: 8, ingredients: ["2 hard-boiled eggs", "baby carrots"], dietTags: ["Low Carb", "Quick"]),
  MealDef(id: "meal-trail-mix", name: "Trail Mix", mealType: "snacks", calories: 240, protein: 7, carbs: 26, fats: 13, ingredients: ["1/4 cup mixed nuts", "dried fruit"], dietTags: ["Vegan", "Quick"]),
  MealDef(id: "meal-berry-protein-smoothie", name: "Berry Protein Smoothie", mealType: "smoothies", calories: 300, protein: 26, carbs: 36, fats: 6, ingredients: ["1 scoop protein powder", "1 cup mixed berries", "1 cup almond milk"], dietTags: ["High Protein", "Quick"]),
  MealDef(id: "meal-green-smoothie", name: "Green Detox Smoothie", mealType: "smoothies", calories: 220, protein: 8, carbs: 40, fats: 4, ingredients: ["spinach", "1 banana", "1 cup coconut water"], dietTags: ["Vegan", "Quick"]),
  MealDef(id: "meal-choc-pb-smoothie", name: "Chocolate Peanut Butter Smoothie", mealType: "smoothies", calories: 380, protein: 30, carbs: 34, fats: 14, ingredients: ["1 scoop chocolate protein", "1 tbsp peanut butter", "1 cup milk"], dietTags: ["High Protein"]),
  MealDef(id: "meal-mango-smoothie", name: "Tropical Mango Smoothie", mealType: "smoothies", calories: 260, protein: 10, carbs: 48, fats: 4, ingredients: ["1 cup mango", "1/2 cup Greek yogurt", "1/2 cup orange juice"], dietTags: ["Quick"]),
];

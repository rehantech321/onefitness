/// One deduplicated/summed grocery line, derived from every meal's
/// ingredients — mirrors nutritionHelpers.js `buildGroceryList` output.
class IngredientGroceryItem {
  const IngredientGroceryItem({required this.item, this.qty, this.unit});

  final String item;
  final num? qty;
  final String? unit;
}

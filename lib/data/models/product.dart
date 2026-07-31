/// Mirrors a sellable fee-item catalog entry (ManageProducts.jsx) — used by
/// the "Fee Item" picker on one-time packages.
class Product {
  const Product({required this.id, required this.name, this.priceCents = 0, this.category, this.archived = false});

  final String id;
  final String name;
  final int priceCents;
  final String? category;
  final bool archived;
}

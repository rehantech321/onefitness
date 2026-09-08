/// One size variant of a [Product], with its own stock count. Inventory is
/// tracked per size because that's the level at which it actually runs out —
/// a product can be well stocked overall and still have no larges left.
class ProductSize {
  const ProductSize({required this.label, this.inventory = 0});

  /// "S", "M", "L", "One Size" — free text so a gym can use whatever sizing
  /// its merchandise actually comes in.
  final String label;
  final int inventory;

  bool get inStock => inventory > 0;
}

/// A sellable item: gym merchandise a client can buy outright, and (as
/// before) the fee-item catalogue that one-time packages attach charges to.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.description,
    this.priceCents = 0,
    this.category,
    this.archived = false,
    this.photos = const [],
    this.sizes = const [],
  });

  final String id;
  final String name;
  final String? description;
  final int priceCents;
  final String? category;
  final bool archived;

  /// Data URLs, same convention as progress photos. First one is the cover
  /// shown in the shop grid.
  final List<String> photos;

  final List<ProductSize> sizes;

  /// Derived, never stored: a persisted total would silently drift out of
  /// step with the per-size counts every time stock moved.
  int get totalInventory => sizes.fold(0, (sum, s) => sum + s.inventory);

  bool get inStock => totalInventory > 0;

  /// Sizes a client can actually pick right now.
  List<ProductSize> get availableSizes => sizes.where((s) => s.inStock).toList();
}

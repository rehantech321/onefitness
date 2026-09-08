import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/product.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ManageProducts.jsx — the fee-item catalog (initiation fees, gear
/// charges, etc.) used by the package "Fee Item" picker. A product a
/// package's `feeItemProductId` still points to can be archived but never
/// deleted (matches web's `inUseBy` guard) — packages already using it keep
/// working; it just disappears from new packages' Fee Item picker.
class ManageProductsScreen extends ConsumerStatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  ConsumerState<ManageProductsScreen> createState() =>
      _ManageProductsScreenState();
}

class _ManageProductsScreenState extends ConsumerState<ManageProductsScreen> {
  Product? _editing;
  bool _creating = false;

  int _inUseBy(String productId) => ref
      .watch(membershipPlansProvider)
      .where((p) => p.feeItemProductId == productId)
      .length;

  Future<void> _removeOrArchive(Product p) async {
    final inUse = _inUseBy(p.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('${inUse > 0 ? "Archive" : "Delete"} "${p.name}"?'),
        content: Text(
          inUse > 0
              ? "$inUse package(s) use this as their Fee Item. Archiving hides it from new packages; packages already using it keep working."
              : "No packages use this product, so it can be permanently removed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Yes, ${inUse > 0 ? "archive" : "delete"} it"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (inUse > 0) {
        final archivedProduct = Product(
          id: p.id,
          name: p.name,
          priceCents: p.priceCents,
          category: p.category,
          archived: true,
        );
        await SupabaseService.upsertProduct(archivedProduct);
        ref.read(productsProvider.notifier).upsert(archivedProduct);
      } else {
        await SupabaseService.deleteProduct(p.id);
        ref.read(productsProvider.notifier).remove(p.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't ${inUse > 0 ? "archive" : "delete"} — check your connection and try again.",
            ),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _editing = null);
  }

  Future<void> _restore(Product p) async {
    final restored = Product(
      id: p.id,
      name: p.name,
      priceCents: p.priceCents,
      category: p.category,
      archived: false,
    );
    try {
      await SupabaseService.upsertProduct(restored);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't restore — check your connection and try again.",
            ),
          ),
        );
      }
      return;
    }
    ref.read(productsProvider.notifier).upsert(restored);
    if (mounted) setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    if (_editing != null || _creating) {
      final editingProduct = _editing;
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        child: _ProductEditForm(
          initial: editingProduct,
          onCancel: () => setState(() {
            _editing = null;
            _creating = false;
          }),
          onSave: (p) async {
            try {
              await SupabaseService.upsertProduct(p);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't save — check your connection and try again.",
                    ),
                  ),
                );
              }
              return;
            }
            ref.read(productsProvider.notifier).upsert(p);
            setState(() {
              _editing = null;
              _creating = false;
            });
          },
          onDelete: editingProduct == null
              ? null
              : () => _removeOrArchive(editingProduct),
          onRestore: editingProduct == null || !editingProduct.archived
              ? null
              : () => _restore(editingProduct),
          isInUse: editingProduct == null ? false : _inUseBy(editingProduct.id) > 0,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Products"),
          const SizedBox(height: 8),
          const HintBox(
            text:
                'The fee items your One-Time Payment packages can charge for (the "Fee Item" picker in Package Setup). Products referenced by a package can be archived but never deleted.',
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            const HintBox(text: "No products yet — add one below."),
          ...products.map((p) {
            final inUse = _inUseBy(p.id);
            return AppCard(
              onTap: () => setState(() => _editing = p),
              child: Opacity(
                opacity: p.archived ? 0.55 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (p.archived) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.line,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    "Archived",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.mute,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            "\$${(p.priceCents / 100).toStringAsFixed(2)} · ${p.category ?? 'Uncategorized'} · used by $inUse package${inUse != 1 ? "s" : ""}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mute,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 15,
                      color: AppColors.mute,
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          BtnGold(
            full: true,
            onPressed: () => setState(() => _creating = true),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 15),
                SizedBox(width: 6),
                Text("Add New Product"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductEditForm extends ConsumerStatefulWidget {
  const _ProductEditForm({
    required this.initial,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
    required this.onRestore,
    required this.isInUse,
  });
  final Product? initial;
  final VoidCallback onCancel;
  final ValueChanged<Product> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;
  final bool isInUse;

  @override
  ConsumerState<_ProductEditForm> createState() => _ProductEditFormState();
}

class _ProductEditFormState extends ConsumerState<_ProductEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late final _price = TextEditingController(
    text: widget.initial != null
        ? (widget.initial!.priceCents / 100).toStringAsFixed(2)
        : "",
  );
  late final _description = TextEditingController(text: widget.initial?.description ?? "");
  String? _category;
  bool _addingCategory = false;
  final _newCategory = TextEditingController();

  /// Working copies of the size rows. Held as plain label/count pairs rather
  /// than ProductSize objects so a half-typed row (blank label, blank count)
  /// is representable while editing.
  late List<({TextEditingController label, TextEditingController qty})> _sizes;
  late List<String> _photos;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initial?.category;
    _photos = [...(widget.initial?.photos ?? const [])];
    final existing = widget.initial?.sizes ?? const <ProductSize>[];
    _sizes = existing.isEmpty
        // A brand-new product starts with one row already there: inventory
        // lives on sizes, so a product with none is unsellable, and an empty
        // list would quietly produce exactly that.
        ? [(label: TextEditingController(text: "One Size"), qty: TextEditingController(text: "0"))]
        : existing
            .map((sz) => (
                  label: TextEditingController(text: sz.label),
                  qty: TextEditingController(text: "${sz.inventory}"),
                ))
            .toList();
  }

  int get _totalInventory => _sizes.fold(0, (sum, r) => sum + (int.tryParse(r.qty.text.trim()) ?? 0));

  List<ProductSize> _collectSizes() => _sizes
      .map((r) => ProductSize(
            label: r.label.text.trim(),
            inventory: int.tryParse(r.qty.text.trim()) ?? 0,
          ))
      .where((sz) => sz.label.isNotEmpty)
      .toList();

  Future<void> _addPhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      final data = await pickProgressPhotoDataUrl();
      if (data != null && mounted) setState(() => _photos = [..._photos, data]);
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    _newCategory.dispose();
    for (final r in _sizes) {
      r.label.dispose();
      r.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    try {
      await SupabaseService.insertPackageCategory(name);
      ref.read(packageCategoriesProvider.notifier).add(name);
      setState(() {
        _category = name;
        _addingCategory = false;
        _newCategory.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't add that category — check your connection and try again.",
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(
            onBack: widget.onCancel,
            title: widget.initial != null ? "Edit Product" : "New Product",
          ),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Name",
            child: AppField(
              controller: _name,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Description",
            child: AppField(
              controller: _description,
              maxLines: 4,
              minLines: 2,
              placeholder: "What is it? Fabric, fit, anything a buyer should know.",
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Price (\$)",
            child: AppField(
              controller: _price,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(height: 14),
          _PhotoStrip(
            photos: _photos,
            busy: _pickingPhoto,
            onAdd: _addPhoto,
            onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
          ),
          const SizedBox(height: 14),
          _SizeInventoryEditor(
            rows: _sizes,
            total: _totalInventory,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => _sizes = [
                  ..._sizes,
                  (label: TextEditingController(), qty: TextEditingController(text: "0")),
                ]),
            onRemove: (i) => setState(() {
              _sizes[i].label.dispose();
              _sizes[i].qty.dispose();
              _sizes = [..._sizes]..removeAt(i);
            }),
          ),
          const SizedBox(height: 14),
          const Text(
            "Category",
            style: TextStyle(
              color: AppColors.mute,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in categories)
                InkWell(
                  onTap: () => setState(() => _category = c),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _category == c ? AppColors.gold : AppColors.line,
                      ),
                      color: _category == c
                          ? AppColors.gold.withValues(alpha: 0.15)
                          : AppColors.bg,
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _category == c ? AppColors.gold : AppColors.txt,
                      ),
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => setState(() => _addingCategory = true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.mute,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                child: const Text(
                  "+ Add category",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_addingCategory) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    controller: _newCategory,
                    placeholder: "e.g. Fees, Apparel",
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _addCategory, child: const Text("Add")),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(
                          Product(
                            id:
                                widget.initial?.id ??
                                "product-${DateTime.now().microsecondsSinceEpoch}",
                            name: _name.text.trim(),
                            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
                            priceCents: (((double.tryParse(_price.text.trim()) ?? 0) * 100).round()).clamp(0, 1 << 31),
                            category: _category,
                            archived: widget.initial?.archived ?? false,
                            photos: _photos,
                            sizes: _collectSizes(),
                          ),
                        ),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onRestore != null) ...[
            const SizedBox(height: 10),
            BtnGhost(
              onPressed: widget.onRestore,
              full: true,
              child: const Text("Restore product"),
            ),
          ] else if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
              ),
              child: Text(widget.isInUse ? "Archive product (hide from new packages)" : "Delete product"),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal strip of product photos with add/remove. The first photo is the
/// cover shown in the client-facing shop, so order matters — hence removal
/// rather than replacement, letting the owner promote a photo by deleting the
/// ones before it.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.busy, required this.onAdd, required this.onRemove});

  final List<String> photos;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text("Photos", style: TextStyle(color: AppColors.mute, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: busy ? null : onAdd,
              style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: Text(busy ? "Adding…" : "+ Add photo", style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (photos.isEmpty)
          const HintBox(text: "No photos yet. The first one becomes the cover image in the shop.", bordered: false)
        else
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ProductPhoto(dataUrl: photos[i], width: 88, height: 88),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(4)),
                        child: const Text("COVER", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.black)),
                      ),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: InkWell(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Per-size stock rows plus a running total. The total is shown, never typed:
/// it's the sum of the rows, so there's no way for it to disagree with them.
class _SizeInventoryEditor extends StatelessWidget {
  const _SizeInventoryEditor({
    required this.rows,
    required this.total,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final List<({TextEditingController label, TextEditingController qty})> rows;
  final int total;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("Sizes & inventory", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: total > 0 ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                  border: Border.all(color: total > 0 ? AppColors.goldDim : AppColors.line),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$total in stock",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: total > 0 ? AppColors.gold : AppColors.mute,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Total is added up from the rows below — a size with 0 left still shows in the shop, marked sold out.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppField(
                      controller: rows[i].label,
                      placeholder: "Size (S, M, L…)",
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppField(
                      controller: rows[i].qty,
                      keyboardType: TextInputType.number,
                      placeholder: "Qty",
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  IconButton(
                    onPressed: rows.length == 1 ? null : () => onRemove(i),
                    icon: Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: rows.length == 1 ? AppColors.line : AppColors.errorText,
                    ),
                    padding: const EdgeInsets.only(left: 6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: onAdd,
            style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            child: const Text("+ Add size", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

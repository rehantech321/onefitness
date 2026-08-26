import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
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
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel("Products (${products.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: const Text(
                  "Product",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const HintBox(
            text:
                "Products referenced by a package can be archived but never deleted.",
          ),
          if (products.isEmpty)
            const HintBox(
              text:
                  "No products yet — add fee items like initiation fees or gear charges.",
            ),
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
                            "${p.category ?? 'Uncategorized'} · \$${(p.priceCents / 100).toStringAsFixed(2)} · used by $inUse package${inUse != 1 ? "s" : ""}",
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
  });
  final Product? initial;
  final VoidCallback onCancel;
  final ValueChanged<Product> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

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
  String? _category;
  bool _addingCategory = false;
  final _newCategory = TextEditingController();

  @override
  void initState() {
    super.initState();
    _category = widget.initial?.category;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _newCategory.dispose();
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
            label: "Price (\$)",
            child: AppField(
              controller: _price,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(height: 10),
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
                            priceCents:
                                ((double.tryParse(_price.text.trim()) ?? 0) *
                                        100)
                                    .round(),
                            category: _category,
                            archived: widget.initial?.archived ?? false,
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
              child: const Text("Delete or archive product"),
            ),
          ],
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/product.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ManageProducts.jsx — the fee-item catalog (initiation fees, gear
/// charges, etc.) used by the package "Fee Item" picker.
class ManageProductsScreen extends ConsumerStatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  ConsumerState<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

class _ManageProductsScreenState extends ConsumerState<ManageProductsScreen> {
  Product? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    if (_editing != null || _creating) {
      return _ProductEditForm(
        initial: _editing,
        onCancel: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        onSave: (p) async {
          try {
            await SupabaseService.upsertProduct(p);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
            }
            return;
          }
          ref.read(productsProvider.notifier).upsert(p);
          setState(() {
            _editing = null;
            _creating = false;
          });
        },
        onDelete: _editing == null
            ? null
            : () async {
                final id = _editing!.id;
                try {
                  await SupabaseService.deleteProduct(id);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete — check your connection and try again.")));
                  }
                  return;
                }
                ref.read(productsProvider.notifier).remove(id);
                setState(() => _editing = null);
              },
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
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text("Product", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          if (products.isEmpty) const HintBox(text: "No products yet — add fee items like initiation fees or gear charges."),
          ...products.map((p) => AppCard(
                onTap: () => setState(() => _editing = p),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          Text("${p.category ?? 'Uncategorized'} · \$${(p.priceCents / 100).toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ProductEditForm extends StatefulWidget {
  const _ProductEditForm({required this.initial, required this.onCancel, required this.onSave, required this.onDelete});
  final Product? initial;
  final VoidCallback onCancel;
  final ValueChanged<Product> onSave;
  final VoidCallback? onDelete;

  @override
  State<_ProductEditForm> createState() => _ProductEditFormState();
}

class _ProductEditFormState extends State<_ProductEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late final _price = TextEditingController(text: widget.initial != null ? (widget.initial!.priceCents / 100).toStringAsFixed(2) : "");
  late final _category = TextEditingController(text: widget.initial?.category ?? "");

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Product" : "New Product"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Name", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Price (\$)", child: AppField(controller: _price, keyboardType: TextInputType.number)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Category", child: AppField(controller: _category, placeholder: "e.g. Fees, Apparel")),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(Product(
                            id: widget.initial?.id ?? "product-${DateTime.now().microsecondsSinceEpoch}",
                            name: _name.text.trim(),
                            priceCents: ((double.tryParse(_price.text.trim()) ?? 0) * 100).round(),
                            category: _category.text.trim().isEmpty ? null : _category.text.trim(),
                          )),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: widget.onDelete, style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)), child: const Text("Delete product")),
          ],
        ],
      ),
    );
  }
}

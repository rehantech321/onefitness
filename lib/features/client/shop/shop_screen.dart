import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/payments/payment_sheet_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/product.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Client-facing merchandise shop. Two states: a responsive grid of what's
/// for sale, and a detail view with photos, size picker and checkout.
///
/// Sold-out sizes are shown greyed rather than hidden — someone looking for a
/// large wants to know it exists and is gone, not be left wondering whether
/// it's ever stocked.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  String? _openProductId;

  @override
  Widget build(BuildContext context) {
    // Only sellable merchandise: the products catalogue is shared with the
    // fee-items packages attach charges to, and those have no photos, no
    // sizes and aren't things a client should be browsing.
    final products = ref
        .watch(productsProvider)
        .where((p) => !p.archived && p.priceCents > 0 && p.sizes.isNotEmpty)
        .toList();

    final open = products.where((p) => p.id == _openProductId).firstOrNull;
    if (open != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _openProductId = null),
        child: _ProductDetail(
          product: open,
          onBack: () => setState(() => _openProductId = null),
        ),
      );
    }

    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(text: "Nothing in the shop just yet — check back soon."),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive by available width rather than a device guess, so it
        // adapts to phones, tablets and split-screen alike.
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
                ? 3
                : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(18),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            // Tall enough for a square image plus two lines of text and the
            // price; the card itself lays out from this.
            childAspectRatio: 0.68,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => _ProductCard(
            product: products[i],
            onTap: () => setState(() => _openProductId = products[i].id),
          ),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = !product.inStock;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductPhoto(dataUrl: product.photos.isEmpty ? null : product.photos.first),
                  if (soldOut)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: const Text(
                        "SOLD OUT",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "\$${(product.priceCents / 100).toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetail extends ConsumerStatefulWidget {
  const _ProductDetail({required this.product, required this.onBack});

  final Product product;
  final VoidCallback onBack;

  @override
  ConsumerState<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<_ProductDetail> {
  String? _size;
  int _photoIndex = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-select when there's only one thing to pick, so a one-size product
    // doesn't make the buyer tap a pointless choice.
    final available = widget.product.availableSizes;
    if (available.length == 1) _size = available.first.label;
  }

  Future<void> _buy() async {
    final size = _size;
    if (size == null) {
      setState(() => _error = "Choose a size first.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await PaymentSheetService.purchaseProduct(
      productId: widget.product.id,
      size: size,
      businessName: ref.read(platformSettingsProvider).businessName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.cancelled) return;
    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Payment received — your order is confirmed.")),
    );
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Shop"),
          const SizedBox(height: 12),
          if (p.photos.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: ProductPhoto(dataUrl: p.photos[_photoIndex.clamp(0, p.photos.length - 1)]),
              ),
            ),
            if (p.photos.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.photos.length,
                  separatorBuilder: (context, i) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => InkWell(
                    onTap: () => setState(() => _photoIndex = i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: i == _photoIndex ? AppColors.gold : AppColors.line, width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ProductPhoto(dataUrl: p.photos[i], width: 52, height: 52),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 4),
          Text(
            "\$${(p.priceCents / 100).toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.gold),
          ),
          if ((p.description ?? "").isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.description!, style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5)),
          ],
          const SizedBox(height: 18),
          const Text("SIZE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: p.sizes.map((sz) {
              final selected = sz.label == _size;
              final out = !sz.inStock;
              return InkWell(
                onTap: out ? null : () => setState(() {
                  _size = sz.label;
                  _error = null;
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
                    border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    out ? "${sz.label} — sold out" : sz.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: out ? AppColors.line : (selected ? AppColors.gold : AppColors.txt),
                      decoration: out ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Only surfaced when it's actually scarce — a plain "12 in stock"
          // on everything is noise, but "only 2 left" is worth knowing.
          if (_size != null)
            Builder(builder: (context) {
              final picked = p.sizes.where((s) => s.label == _size).firstOrNull;
              if (picked == null || picked.inventory > 3 || picked.inventory <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  "Only ${picked.inventory} left in ${picked.label}.",
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD68A4F), fontWeight: FontWeight.w600),
                ),
              );
            }),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          BtnGold(
            full: true,
            onPressed: (_busy || !p.inStock) ? null : _buy,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.creditCard, size: 15),
                const SizedBox(width: 8),
                Text(_busy ? "Working…" : (p.inStock ? "Buy now" : "Sold out")),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

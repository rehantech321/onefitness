import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/progress_photo.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors ProgressPhotos.jsx — upload progress photos and view them in a
/// 2-column grid with the date + delete overlaid.
class ProgressPhotosTab extends ConsumerStatefulWidget {
  const ProgressPhotosTab({super.key});

  @override
  ConsumerState<ProgressPhotosTab> createState() => _ProgressPhotosTabState();
}

class _ProgressPhotosTabState extends ConsumerState<ProgressPhotosTab> {
  bool _busy = false;

  Future<void> _addPhoto() async {
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(
              photos: [ProgressPhoto(id: DateTime.now().microsecondsSinceEpoch.toString(), date: isoToday(), bytes: bytes), ...r.photos],
            ));
      }
    } catch (_) {
      // No permission / user cancelled — nothing to log for a demo picker.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(String id) {
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(photos: r.photos.where((p) => p.id != id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(clientRecordProvider).photos;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Progress Photos"),
              TextButton.icon(
                onPressed: _busy ? null : _addPhoto,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(LucideIcons.camera, size: 14),
                label: Text(_busy ? "Adding…" : "Add photo", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (photos.isEmpty)
            const HintBox(text: "No photos yet. Add progress photos to track visual change over time.")
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 3 / 4,
              children: photos.map((p) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: AppColors.card, child: Image.memory(p.bytes, fit: BoxFit.cover)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(dayLabel(p.date), style: const TextStyle(fontSize: 11, color: Colors.white)),
                              InkWell(
                                onTap: () => _remove(p.id),
                                child: const Icon(LucideIcons.trash2, size: 13, color: Color(0xFFE0A0A0)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

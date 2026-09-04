import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/progress_photo.dart";
import "../../../data/models/squad_chat_message.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";

/// Mirrors ProgressPhotos.jsx — upload progress photos and view them in a
/// 2-column grid with the date + delete overlaid.
class ProgressPhotosTab extends ConsumerStatefulWidget {
  const ProgressPhotosTab({super.key});

  @override
  ConsumerState<ProgressPhotosTab> createState() => _ProgressPhotosTabState();
}

class _ProgressPhotosTabState extends ConsumerState<ProgressPhotosTab> {
  bool _busy = false;
  String? _removingId;
  String? _sharingId;
  String? _error;

  Future<void> _shareWithSquad(ProgressPhoto p) async {
    if (_sharingId != null) return;
    final info = ref.read(clientInfoProvider);
    final squad = ref.read(squadsProvider.notifier).squadFor(info.id);
    if (squad == null) return;
    final entry = SquadChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      from: info.id,
      at: stamp(),
      type: "shared_progress",
      shareKind: "photo",
      payload: {"img": p.img, "date": p.date},
    );
    setState(() => _sharingId = p.id);
    final ok = await mutateSquad(ref, squad, (s) => s.copyWith(chat: [entry, ...s.chat]));
    if (!mounted) return;
    setState(() => _sharingId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Shared to Squad chat" : "Couldn't share — check your connection and try again.")),
    );
  }

  Future<void> _addPhoto() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final img = await pickProgressPhotoDataUrl();
      if (img == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final client = ref.read(clientRecordProvider);
      final next = [ProgressPhoto(id: DateTime.now().microsecondsSinceEpoch.toString(), date: isoToday(), img: img), ...client.photos];
      await SupabaseService.updateClientPhotos(client.id, next);
      ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(photos: next));
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't save that photo — check your connection and try again.";
        });
      }
    }
  }

  Future<void> _remove(String id) async {
    if (_removingId != null) return;
    final client = ref.read(clientRecordProvider);
    final next = client.photos.where((p) => p.id != id).toList();
    setState(() {
      _removingId = id;
      _error = null;
    });
    try {
      await SupabaseService.updateClientPhotos(client.id, next);
      ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(photos: next));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't delete — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(clientRecordProvider).photos;
    final info = ref.watch(clientInfoProvider);
    final squad = ref.watch(squadsProvider.notifier).squadFor(info.id);

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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
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
                final hasComment = p.coachComment != null && p.coachComment!.isNotEmpty;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: AppColors.card, child: Image.memory(p.bytes, fit: BoxFit.cover)),
                      if (hasComment)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: InkWell(
                            onTap: () => showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.card,
                                title: const Text("Coach's note", style: TextStyle(fontSize: 14)),
                                content: Text(p.coachComment!, style: const TextStyle(fontSize: 13)),
                                actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Close"))],
                              ),
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                              child: const Icon(LucideIcons.messageSquare, size: 13, color: Colors.white),
                            ),
                          ),
                        ),
                      if (squad != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _sharingId == p.id
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                                )
                              : InkWell(
                                  onTap: _sharingId == null ? () => _shareWithSquad(p) : null,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                                    child: const Icon(LucideIcons.users2, size: 13, color: Colors.white),
                                  ),
                                ),
                        ),
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
                              _removingId == p.id
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE0A0A0)),
                                    )
                                  : InkWell(
                                      onTap: _removingId == null ? () => _remove(p.id) : null,
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

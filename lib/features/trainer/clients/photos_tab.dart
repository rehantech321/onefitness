import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach-side view of a client's progress photos — this app's first,
/// there's no earlier tab for it (see Notifications spec audit). Read-only
/// gallery plus one comment box per photo (Notifications spec — "Coach
/// comments on a progress photo").
class PhotosTab extends ConsumerStatefulWidget {
  const PhotosTab({super.key, required this.clientId});
  final String clientId;

  @override
  ConsumerState<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends ConsumerState<PhotosTab> {
  final Map<String, TextEditingController> _controllers = {};
  String? _savingId;

  TextEditingController _controllerFor(String id, String? current) =>
      _controllers.putIfAbsent(id, () => TextEditingController(text: current ?? ""));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveComment(String photoId) async {
    final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
    if (record == null) return;
    final text = _controllers[photoId]?.text.trim() ?? "";
    setState(() => _savingId = photoId);
    try {
      final next = record.photos.map((p) => p.id == photoId ? p.copyWith(coachComment: text, coachCommentAt: stamp()) : p).toList();
      await SupabaseService.updateClientPhotos(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(photos: next));
      if (text.isNotEmpty) {
        final info = ref.read(trainerRosterProvider).where((c) => c.id == widget.clientId);
        if (info.isNotEmpty) {
          notifyCoachComment(toEmail: info.first.email ?? "", toName: info.first.name, kind: "progress photo");
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Comment saved.")));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(trainerClientRecordsProvider)[widget.clientId];
    final photos = (record?.photos ?? const []).toList()..sort((a, b) => b.date.compareTo(a.date));

    if (photos.isEmpty) {
      return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "No progress photos yet."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Progress Photos"),
          ...photos.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(p.bytes, fit: BoxFit.cover, width: double.infinity, height: 220),
                      ),
                      const SizedBox(height: 6),
                      Text(p.date, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                      const SizedBox(height: 10),
                      const Text("COACH COMMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mute, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      AppField(controller: _controllerFor(p.id, p.coachComment), placeholder: "Leave a note on this photo…", maxLines: 2),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: BtnGhost(
                          onPressed: _savingId == p.id ? null : () => _saveComment(p.id),
                          child: Text(_savingId == p.id ? "Saving…" : "Save comment"),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

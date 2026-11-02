import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/utils/write_failure.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/progress_photo.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach-side view of a client's progress photos — the gallery, one comment
/// box per photo (Notifications spec — "Coach comments on a progress
/// photo"), and adding a photo on the client's behalf.
///
/// Staff add photos because the useful ones are usually taken in the gym, on
/// the coach's phone, at the assessment — and before this the only way in
/// was to send them to the client and ask them to upload them again.
/// Anything staff add is stamped with their name so the client can tell it
/// from one of their own.
class PhotosTab extends ConsumerStatefulWidget {
  const PhotosTab({super.key, required this.clientId});
  final String clientId;

  @override
  ConsumerState<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends ConsumerState<PhotosTab> {
  final Map<String, TextEditingController> _controllers = {};
  String? _savingId;
  bool _adding = false;
  String? _addError;

  /// Who to stamp on a photo this coach adds. The owner shows as "Admin"
  /// rather than their own name, matching how they're identified elsewhere.
  String _whoAmI() {
    final auth = ref.read(trainerAuthProvider);
    if (auth == null) return "Coach";
    if (auth == "owner") return "Admin";
    final me = ref.read(trainersProvider).where((t) => t.id == auth);
    return me.isNotEmpty ? me.first.name : "Coach";
  }

  Future<void> _addPhoto() async {
    if (_adding) return;
    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      final img = await pickProgressPhotoDataUrl();
      if (img == null) {
        if (mounted) setState(() => _adding = false);
        return;
      }
      final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
      if (record == null) {
        if (mounted) setState(() => _adding = false);
        return;
      }
      final photo = ProgressPhoto(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        date: isoToday(),
        img: img,
        addedBy: _whoAmI(),
      );
      final next = [photo, ...record.photos];
      await SupabaseService.updateClientPhotos(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(photos: next));
      // A photo turning up in someone's own progress gallery without a word
      // is startling. Push only — a coach may add several in a session, and
      // a text each time is how people switch notifications off.
      notifyPush(
        profileId: widget.clientId,
        title: "New progress photo",
        body: "${photo.addedBy} added a progress photo to your gallery.",
      );
      if (mounted) setState(() => _adding = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _adding = false;
          _addError = writeFailureMessage(e, whatFailed: "Couldn't add that photo");
        });
      }
    }
  }

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
          notifyCoachComment(toEmail: info.first.email ?? "", toName: info.first.name, kind: "progress photo", profileId: info.first.id);
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

    final addButton = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BtnGhost(
            full: true,
            onPressed: _adding ? null : _addPhoto,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_adding)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.mute)),
                  )
                else
                  const Icon(LucideIcons.camera, size: 15),
                const SizedBox(width: 8),
                Text(_adding ? "Adding…" : "Add a photo for this client"),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              "It appears in their gallery with your name on it, and they're notified.",
              style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
            ),
          ),
          if (_addError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_addError!, style: TextStyle(color: AppColors.danger, fontSize: 12, height: 1.4)),
            ),
        ],
      ),
    );

    if (photos.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("Progress Photos"),
            const SizedBox(height: 8),
            addButton,
            const HintBox(text: "No progress photos yet."),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Progress Photos"),
          const SizedBox(height: 8),
          addButton,
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
                      Row(
                        children: [
                          Text(p.date, style: TextStyle(fontSize: 12, color: AppColors.mute)),
                          if (p.addedBy != null) ...[
                            const SizedBox(width: 8),
                            Tag(text: "Added by ${p.addedBy}"),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text("COACH COMMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mute, letterSpacing: 0.5)),
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

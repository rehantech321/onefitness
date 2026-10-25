import "dart:typed_data";

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart" show compute;
import "package:flutter/material.dart";
import "package:image/image.dart" as img;
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../data/models/intake_schema.dart";

/// The files attached to one intake form — listed for everyone, added and
/// removed by whoever is filling the form in.
///
/// Uploads commit as they happen rather than waiting for "Save & mark
/// complete": the bytes reach the bucket the moment a file is picked, so if
/// the record didn't learn about them until save, closing the form would
/// leave files nothing could reach or clean up. [onChanged] fires after the
/// record has already been updated, so the caller is syncing its own state,
/// not being asked to save.
class IntakeAttachmentsField extends StatefulWidget {
  const IntakeAttachmentsField({
    super.key,
    required this.profileId,
    required this.assessmentKey,
    required this.attachments,
    required this.onChanged,
    this.readOnly = false,
  });

  final String profileId;
  final String assessmentKey;
  final List<IntakeAttachment> attachments;
  final ValueChanged<List<IntakeAttachment>> onChanged;

  /// True on the coach's read-only view of a completed intake, where files
  /// open but nothing can be added or taken away by accident.
  final bool readOnly;

  @override
  State<IntakeAttachmentsField> createState() => _IntakeAttachmentsFieldState();
}

class _IntakeAttachmentsFieldState extends State<IntakeAttachmentsField> {
  bool _busy = false;
  String? _error;

  /// Which attachment is being opened, so its row can say so — minting a
  /// signed URL is a round trip, and a tap with no feedback reads as a dead
  /// control.
  String? _opening;

  int get _remaining => kMaxIntakeAttachments - widget.attachments.length;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _error = null);
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ["pdf", "jpg", "jpeg"],
        withData: true,
        allowMultiple: true,
      );
    } catch (_) {
      setState(() => _error = "Couldn't open the file picker.");
      return;
    }
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;

    // Taking the first N rather than refusing the whole selection: the files
    // they picked first are the ones they were most deliberate about, and
    // rejecting all six because they chose seven helps no one.
    final accepted = files.take(_remaining).toList();
    final overflow = files.length - accepted.length;

    setState(() => _busy = true);
    var next = [...widget.attachments];
    final failures = <String>[];

    for (final file in accepted) {
      final bytes = file.bytes;
      if (bytes == null) {
        failures.add("${file.name} couldn't be read");
        continue;
      }
      final contentType = _contentTypeFor(file.name);
      if (contentType == null) {
        failures.add("${file.name} isn't a PDF or JPEG");
        continue;
      }
      var payload = bytes;
      // A photographed document can easily clear 10MB. Shrinking it beats
      // rejecting it — the page stays legible at 2000px — but a PDF can't be
      // re-encoded this way, so an oversized one is still a refusal.
      if (payload.length > SupabaseService.kIntakeFileMaxBytes && contentType == "image/jpeg") {
        payload = await compute(_shrinkJpeg, payload) ?? payload;
      }
      if (payload.length > SupabaseService.kIntakeFileMaxBytes) {
        failures.add("${file.name} is over ${_fmtSize(SupabaseService.kIntakeFileMaxBytes)}");
        continue;
      }
      try {
        final attachment = await SupabaseService.uploadIntakeFile(
          profileId: widget.profileId,
          assessmentKey: widget.assessmentKey,
          name: file.name,
          bytes: payload,
          contentType: contentType,
        );
        next = [...next, attachment];
      } catch (_) {
        failures.add("${file.name} didn't upload");
      }
    }

    if (next.length != widget.attachments.length) {
      try {
        await SupabaseService.updateClientIntakeAttachments(
          widget.profileId,
          widget.assessmentKey,
          next,
        );
        widget.onChanged(next);
      } catch (_) {
        failures.add("the upload couldn't be saved to this form");
      }
    }

    final notes = [
      if (overflow > 0)
        "Only $kMaxIntakeAttachments files can be attached, so ${overflow == 1 ? "one was" : "$overflow were"} left out.",
      if (failures.isNotEmpty) "Couldn't add ${failures.join(", ")}.",
    ];
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = notes.isEmpty ? null : notes.join(" ");
    });
  }

  Future<void> _remove(IntakeAttachment a) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text("Remove “${a.name}” from this form?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final next = widget.attachments.where((x) => x.id != a.id).toList();
    try {
      // The record first: if the file were deleted and the record then failed
      // to save, the form would keep pointing at bytes that no longer exist.
      // This order can leave an unreferenced object behind instead, which is
      // invisible rather than broken.
      await SupabaseService.updateClientIntakeAttachments(
        widget.profileId,
        widget.assessmentKey,
        next,
      );
      widget.onChanged(next);
      await SupabaseService.deleteIntakeFile(a.path);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't remove that file — check your connection and try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(IntakeAttachment a) async {
    if (_opening != null) return;
    setState(() {
      _opening = a.id;
      _error = null;
    });
    try {
      final url = await SupabaseService.signedIntakeFileUrl(a.path);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => _error = "Nothing on this device could open “${a.name}”.");
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open “${a.name}” — check your connection and try again.");
    }
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments;
    if (widget.readOnly && attachments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.paperclip, size: 15, color: AppColors.gold),
            const SizedBox(width: 7),
            Text(
              widget.readOnly
                  ? "Attached files (${attachments.length})"
                  : "Attachments (${attachments.length} of $kMaxIntakeAttachments)",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (!widget.readOnly)
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Text(
              "Optional. Add bloodwork, a doctor's or dietitian's note, or a plan you're already following — PDF or JPEG.",
              style: TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.45),
            ),
          ),
        const SizedBox(height: 10),
        ...attachments.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AttachmentRow(
              attachment: a,
              opening: _opening == a.id,
              onOpen: () => _open(a),
              onRemove: widget.readOnly || _busy ? null : () => _remove(a),
            ),
          ),
        ),
        if (!widget.readOnly) ...[
          if (_remaining > 0)
            OutlinedButton(
              onPressed: _busy ? null : _pick,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.mute,
                side: const BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.mute)),
                    )
                  else
                    const Icon(LucideIcons.upload, size: 15),
                  const SizedBox(width: 8),
                  Text(_busy ? "Uploading…" : (attachments.isEmpty ? "Add a file" : "Add another")),
                ],
              ),
            )
          else
            const Text(
              "That's the maximum. Remove one to add a different file.",
              style: TextStyle(fontSize: 11.5, color: AppColors.mute),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFE05555), fontSize: 12, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.opening,
    required this.onOpen,
    required this.onRemove,
  });

  final IntakeAttachment attachment;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return InkWell(
      onTap: opening ? null : onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              a.isPdf ? LucideIcons.fileText : LucideIcons.image,
              size: 16,
              color: AppColors.mute,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    opening
                        ? "Opening…"
                        : "${a.isPdf ? "PDF" : "JPEG"}${a.size > 0 ? " · ${_fmtSize(a.size)}" : ""}",
                    style: const TextStyle(fontSize: 11, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(LucideIcons.x, size: 15, color: AppColors.mute),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: "Remove",
              )
            else
              const Icon(LucideIcons.externalLink, size: 14, color: AppColors.mute),
          ],
        ),
      ),
    );
  }
}

/// PDF or JPEG only, decided by extension. The picker already filters to
/// these, but a picker filter is a suggestion on some platforms — and the
/// bucket rejects anything else outright, so a guess here would surface as a
/// failed upload rather than as a clear refusal.
String? _contentTypeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  return null;
}

/// Re-encodes an oversized photo to fit. 2000px on the longest edge at
/// quality 82 keeps printed text on a lab report readable, which a smaller
/// bound would not — these are documents to be read, not thumbnails.
Uint8List? _shrinkJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    const maxSide = 2000;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest <= maxSide
        ? decoded
        : (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxSide)
            : img.copyResize(decoded, height: maxSide));
    final out = img.encodeJpg(resized, quality: 82);
    return out.length < bytes.length ? out : null;
  } catch (_) {
    return null;
  }
}

String _fmtSize(int bytes) {
  if (bytes >= 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  if (bytes >= 1024) return "${(bytes / 1024).round()} KB";
  return "$bytes B";
}

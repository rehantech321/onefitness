import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";

/// Report and Block, as required by Apple guideline 1.2: every piece of
/// user content and every user profile needs a way to report it, and users
/// need a way to block each other.
///
/// One sheet used from everywhere — a chat bubble, a coach profile, a
/// review — so the wording and the reasons never drift apart.

const _reasons = <({String key, String label, String hint})>[
  (key: "spam", label: "Spam", hint: "Unwanted or repeated promotional messages"),
  (key: "harassment", label: "Harassment or abuse", hint: "Threats, bullying or hateful language"),
  (key: "inappropriate", label: "Inappropriate content", hint: "Sexual, violent or otherwise offensive"),
  (key: "other", label: "Something else", hint: "Tell us what's wrong"),
];

/// Opens the actions menu for a piece of content or a person.
///
/// [contentType] is "message" | "profile" | "review" | "post" | "bio".
/// [onBlocked] runs after a successful block, so the caller can drop the
/// person out of whatever list it is showing straight away.
Future<void> showReportBlockSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String? reportedUserId,
  required String reportedUserName,
  required String contentType,
  String? contentId,
  String? excerpt,
  VoidCallback? onBlocked,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(LucideIcons.flag, size: 20, color: AppColors.gold),
            title: const Text("Report", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            subtitle: Text(
              contentType == "profile" ? "Report $reportedUserName" : "Report this $contentType",
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              await _showReportReasons(
                context,
                reportedUserId: reportedUserId,
                reportedUserName: reportedUserName,
                contentType: contentType,
                contentId: contentId,
                excerpt: excerpt,
              );
            },
          ),
          if (reportedUserId != null)
            ListTile(
              leading: const Icon(LucideIcons.ban, size: 20, color: AppColors.errorText),
              title: const Text("Block user",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.errorText)),
              subtitle: Text(
                "$reportedUserName won't be able to message you, and you won't see them",
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await _confirmBlock(context, reportedUserId, reportedUserName, onBlocked);
              },
            ),
          ListTile(
            leading: const Icon(LucideIcons.x, size: 20, color: AppColors.mute),
            title: const Text("Cancel", style: TextStyle(fontSize: 15)),
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _showReportReasons(
  BuildContext context, {
  required String? reportedUserId,
  required String reportedUserName,
  required String contentType,
  String? contentId,
  String? excerpt,
}) async {
  String? chosen;
  final noteCtrl = TextEditingController();
  var busy = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) => Padding(
        // Lifts the sheet clear of the keyboard when the note field is open.
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contentType == "profile" ? "Report $reportedUserName" : "Report this $contentType",
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  "We review every report and act within 24 hours.",
                  style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (final r in _reasons)
                  InkWell(
                    onTap: () => setSheetState(() => chosen = r.key),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: chosen == r.key ? AppColors.gold : AppColors.line),
                        color: chosen == r.key ? AppColors.gold.withValues(alpha: 0.12) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            chosen == r.key ? LucideIcons.circleCheck : LucideIcons.circle,
                            size: 17,
                            color: chosen == r.key ? AppColors.gold : AppColors.mute,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.label,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 1),
                                Text(r.hint,
                                    style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Anything else we should know? (optional)",
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.mute),
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: (chosen == null || busy)
                      ? null
                      : () async {
                          setSheetState(() => busy = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await SupabaseService.submitReport(
                              reportedUserId: reportedUserId,
                              contentType: contentType,
                              contentId: contentId,
                              excerpt: excerpt,
                              reason: chosen!,
                              note: noteCtrl.text,
                            );
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("Thanks, we'll review within 24 hours."),
                                duration: Duration(seconds: 4),
                              ),
                            );
                          } catch (e) {
                            setSheetState(() => busy = false);
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("Couldn't send that report — check your connection and try again."),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.line,
                    disabledForegroundColor: AppColors.mute,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(busy ? "Sending…" : "Submit report",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  noteCtrl.dispose();
}

Future<void> _confirmBlock(
  BuildContext context,
  String blockedId,
  String name,
  VoidCallback? onBlocked,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text("Block $name?", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: const Text(
        "You won't see their messages and neither of you will be able to "
        "contact the other. You can undo this from Settings → Blocked users.",
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.mute),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
          child: const Text("Block", style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await SupabaseService.blockUser(blockedId);
    onBlocked?.call();
    messenger.showSnackBar(
      SnackBar(content: Text("$name has been blocked."), duration: const Duration(seconds: 4)),
    );
  } catch (e) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't block just now — check your connection and try again.")),
    );
  }
}

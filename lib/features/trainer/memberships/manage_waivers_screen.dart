import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ManageWaivers.jsx — waiver/contract documents, either a general
/// signup waiver or a plan-specific contract. The source's "rich text"
/// editor is really just a textarea with Markdown-style insert buttons, so
/// that's what this ports. A document someone has already signed can be
/// archived but never deleted (matches web's `docSignedCount` guard) —
/// their signed copy stays valid.
class ManageWaiversScreen extends ConsumerStatefulWidget {
  const ManageWaiversScreen({super.key});

  @override
  ConsumerState<ManageWaiversScreen> createState() =>
      _ManageWaiversScreenState();
}

class _ManageWaiversScreenState extends ConsumerState<ManageWaiversScreen> {
  WaiverDoc? _editing;
  bool _creating = false;

  int _signedCount(String docId) {
    final roster = ref.watch(trainerRosterProvider);
    final records = ref.watch(trainerClientRecordsProvider);
    return roster
        .where(
          (c) => (records[c.id]?.signatures ?? const []).any(
            (s) => s.docId == docId,
          ),
        )
        .length;
  }

  Future<void> _removeOrArchive(WaiverDoc w) async {
    final signed = _signedCount(w.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('${signed > 0 ? "Archive" : "Delete"} "${w.title}"?'),
        content: Text(
          signed > 0
              ? "$signed client(s) have already signed this. Archiving stops it from being required going forward; their signed copy stays exactly as it was."
              : "No one has signed this yet, so it can be permanently removed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Yes, ${signed > 0 ? "archive" : "delete"} it"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (signed > 0) {
        final archived = WaiverDoc(
          id: w.id,
          title: w.title,
          body: w.body,
          scope: w.scope,
          planId: w.planId,
          required: w.required,
          archived: true,
        );
        await SupabaseService.upsertWaiverDoc(archived);
        ref.read(waiversProvider.notifier).upsert(archived);
      } else {
        await SupabaseService.deleteWaiverDoc(w.id);
        ref.read(waiversProvider.notifier).remove(w.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't ${signed > 0 ? "archive" : "delete"} — check your connection and try again.",
            ),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _editing = null);
  }

  Future<void> _restore(WaiverDoc w) async {
    final restored = WaiverDoc(
      id: w.id,
      title: w.title,
      body: w.body,
      scope: w.scope,
      planId: w.planId,
      required: w.required,
      archived: false,
    );
    try {
      await SupabaseService.upsertWaiverDoc(restored);
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
    ref.read(waiversProvider.notifier).upsert(restored);
    if (mounted) setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final waivers = ref.watch(waiversProvider);
    final plans = ref.watch(membershipPlansProvider);

    if (_editing != null || _creating) {
      final editingDoc = _editing;
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        child: _WaiverEditForm(
          initial: editingDoc,
          planNames: {for (final p in plans) p.id: p.name},
          onCancel: () => setState(() {
            _editing = null;
            _creating = false;
          }),
          onSave: (w) async {
            try {
              await SupabaseService.upsertWaiverDoc(w);
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
            ref.read(waiversProvider.notifier).upsert(w);
            setState(() {
              _editing = null;
              _creating = false;
            });
          },
          onDelete: editingDoc == null
              ? null
              : () => _removeOrArchive(editingDoc),
          onRestore: editingDoc == null || !editingDoc.archived
              ? null
              : () => _restore(editingDoc),
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
              SectionLabel("Waivers & Contracts (${waivers.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: const Text(
                  "Document",
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
                "Documents someone has already signed can be archived but never deleted — their signed copy stays valid.",
          ),
          ...waivers.map((w) {
            final signed = _signedCount(w.id);
            return Opacity(
              opacity: w.archived ? 0.55 : 1,
              child: AppCard(
                onTap: () => setState(() => _editing = w),
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
                                  w.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (w.archived) ...[
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
                            "${w.scope == 'plan' ? 'Plan contract' : 'General waiver'}${w.required ? ' · Required' : ''} · $signed signed",
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

class _WaiverEditForm extends StatefulWidget {
  const _WaiverEditForm({
    required this.initial,
    required this.planNames,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
    required this.onRestore,
  });
  final WaiverDoc? initial;
  final Map<String, String> planNames;
  final VoidCallback onCancel;
  final ValueChanged<WaiverDoc> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  State<_WaiverEditForm> createState() => _WaiverEditFormState();
}

class _WaiverEditFormState extends State<_WaiverEditForm> {
  late final _title = TextEditingController(text: widget.initial?.title ?? "");
  late final _body = TextEditingController(text: widget.initial?.body ?? "");
  late String _scope = widget.initial?.scope ?? "general";
  late String? _planId = widget.initial?.planId;
  late bool _required = widget.initial?.required ?? true;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _wrap(String marker) {
    final sel = _body.selection;
    final text = _body.text;
    if (!sel.isValid || sel.isCollapsed) {
      final insert = "$marker$marker";
      _body.text = text.replaceRange(
        sel.start < 0 ? text.length : sel.start,
        sel.start < 0 ? text.length : sel.start,
        insert,
      );
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    _body.text = text.replaceRange(
      sel.start,
      sel.end,
      "$marker$selected$marker",
    );
  }

  /// Inserts a raw token at the cursor (or the end, if nothing's focused)
  /// — used for both merge-token variables and the structural capture
  /// tokens (`{{initial}}` etc.), unlike [_wrap] which wraps a selection.
  void _insertToken(String token) {
    final sel = _body.selection;
    final text = _body.text;
    final at = sel.start < 0 ? text.length : sel.start;
    setState(() {
      _body.text = text.replaceRange(at, sel.end < 0 ? at : sel.end, token);
      _body.selection = TextSelection.collapsed(offset: at + token.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(
            onBack: widget.onCancel,
            title: widget.initial != null ? "Edit Document" : "New Document",
          ),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Title",
            child: AppField(
              controller: _title,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "SCOPE",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _ScopeChip(
                label: "General (signup)",
                selected: _scope == "general",
                onTap: () => setState(() => _scope = "general"),
              ),
              _ScopeChip(
                label: "Plan contract",
                selected: _scope == "plan",
                onTap: () => setState(() => _scope = "plan"),
              ),
            ],
          ),
          if (_scope == "plan") ...[
            const SizedBox(height: 10),
            const Text(
              "PLAN",
              style: TextStyle(
                fontSize: 10,
                color: AppColors.mute,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: widget.planNames.entries
                  .map(
                    (e) => _ScopeChip(
                      label: e.value,
                      selected: _planId == e.key,
                      onTap: () => setState(() => _planId = e.key),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _wrap("**")),
                icon: const Icon(
                  LucideIcons.bold,
                  size: 16,
                  color: AppColors.mute,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _wrap("*")),
                icon: const Icon(
                  LucideIcons.italic,
                  size: 16,
                  color: AppColors.mute,
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _body.text = "${_body.text}\n- "),
                icon: const Icon(
                  LucideIcons.list,
                  size: 16,
                  color: AppColors.mute,
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: "Insert a client variable",
                onSelected: (t) => _insertToken("{{$t}}"),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: "client_first_name", child: Text("First name")),
                  PopupMenuItem(value: "client_last_name", child: Text("Last name")),
                  PopupMenuItem(value: "client_full_name", child: Text("Full name")),
                  PopupMenuItem(value: "client_dob", child: Text("Date of birth")),
                  PopupMenuItem(value: "emergency_contact_name", child: Text("Emergency contact name")),
                  PopupMenuItem(value: "emergency_contact_phone", child: Text("Emergency contact phone")),
                  PopupMenuItem(value: "coach_name", child: Text("Coach name")),
                  PopupMenuItem(value: "signature_date", child: Text("Today's date")),
                  PopupMenuItem(value: "guardian_name", child: Text("Guardian name")),
                ],
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.atSign, size: 14, color: AppColors.mute),
                    SizedBox(width: 3),
                    Text("Variable", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: "Insert a signing capture point",
                onSelected: (t) => _insertToken("{{$t}}"),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: "initial", child: Text("Client Initials box")),
                  PopupMenuItem(value: "signature", child: Text("Client Signature line")),
                  PopupMenuItem(value: "guardian_signature", child: Text("Guardian Signature (if minor)")),
                  PopupMenuItem(value: "photo_opt_out", child: Text("Photo/video opt-out checkbox")),
                ],
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.penTool, size: 14, color: AppColors.gold),
                    SizedBox(width: 3),
                    Text("Sign here…", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              "Insert Client Initials/Signature wherever the client needs to place one — they'll become tap-to-sign boxes when the client reads this document. Variables like {{client_full_name}} are replaced with the client's real info automatically.",
              style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
            ),
          ),
          TextField(
            controller: _body,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.txt, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Document text…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _required = !_required),
            child: Row(
              children: [
                Icon(
                  _required ? LucideIcons.checkSquare : LucideIcons.square,
                  size: 18,
                  color: _required ? AppColors.gold : AppColors.mute,
                ),
                const SizedBox(width: 8),
                const Text("Required", style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed:
                      _title.text.trim().isEmpty || _body.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(
                          WaiverDoc(
                            id:
                                widget.initial?.id ??
                                "waiver-${DateTime.now().microsecondsSinceEpoch}",
                            title: _title.text.trim(),
                            body: _body.text,
                            scope: _scope,
                            planId: _scope == "plan" ? _planId : null,
                            required: _required,
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
              child: const Text("Restore document"),
            ),
          ] else if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
              ),
              child: const Text("Delete or archive document"),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.gold : AppColors.txt,
          ),
        ),
      ),
    );
  }
}

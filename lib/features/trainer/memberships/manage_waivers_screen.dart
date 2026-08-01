import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ManageWaivers.jsx — waiver/contract documents, either a general
/// signup waiver or a plan-specific contract. The source's "rich text"
/// editor is really just a textarea with Markdown-style insert buttons, so
/// that's what this ports.
class ManageWaiversScreen extends ConsumerStatefulWidget {
  const ManageWaiversScreen({super.key});

  @override
  ConsumerState<ManageWaiversScreen> createState() => _ManageWaiversScreenState();
}

class _ManageWaiversScreenState extends ConsumerState<ManageWaiversScreen> {
  WaiverDoc? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final waivers = ref.watch(waiversProvider);
    final plans = ref.watch(membershipPlansProvider);

    if (_editing != null || _creating) {
      return _WaiverEditForm(
        initial: _editing,
        planNames: {for (final p in plans) p.id: p.name},
        onCancel: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        onSave: (w) {
          ref.read(waiversProvider.notifier).upsert(w);
          setState(() {
            _editing = null;
            _creating = false;
          });
        },
        onDelete: _editing == null
            ? null
            : () {
                ref.read(waiversProvider.notifier).remove(_editing!.id);
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
              SectionLabel("Waivers & Contracts (${waivers.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text("Document", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          ...waivers.map((w) => Opacity(
                opacity: w.archived ? 0.55 : 1,
                child: AppCard(
                  onTap: () => setState(() => _editing = w),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text("${w.scope == 'plan' ? 'Plan contract' : 'General waiver'}${w.required ? ' · Required' : ''}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _WaiverEditForm extends StatefulWidget {
  const _WaiverEditForm({required this.initial, required this.planNames, required this.onCancel, required this.onSave, required this.onDelete});
  final WaiverDoc? initial;
  final Map<String, String> planNames;
  final VoidCallback onCancel;
  final ValueChanged<WaiverDoc> onSave;
  final VoidCallback? onDelete;

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
      _body.text = text.replaceRange(sel.start < 0 ? text.length : sel.start, sel.start < 0 ? text.length : sel.start, insert);
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    _body.text = text.replaceRange(sel.start, sel.end, "$marker$selected$marker");
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Document" : "New Document"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Title", child: AppField(controller: _title)),
          const SizedBox(height: 10),
          const Text("SCOPE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            _ScopeChip(label: "General (signup)", selected: _scope == "general", onTap: () => setState(() => _scope = "general")),
            _ScopeChip(label: "Plan contract", selected: _scope == "plan", onTap: () => setState(() => _scope = "plan")),
          ]),
          if (_scope == "plan") ...[
            const SizedBox(height: 10),
            const Text("PLAN", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: widget.planNames.entries.map((e) => _ScopeChip(label: e.value, selected: _planId == e.key, onTap: () => setState(() => _planId = e.key))).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(onPressed: () => setState(() => _wrap("**")), icon: const Icon(LucideIcons.bold, size: 16, color: AppColors.mute)),
              IconButton(onPressed: () => setState(() => _wrap("*")), icon: const Icon(LucideIcons.italic, size: 16, color: AppColors.mute)),
              IconButton(onPressed: () => setState(() => _body.text = "${_body.text}\n- "), icon: const Icon(LucideIcons.list, size: 16, color: AppColors.mute)),
            ],
          ),
          TextField(
            controller: _body,
            maxLines: 8,
            style: const TextStyle(color: AppColors.txt, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Document text…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _required = !_required),
            child: Row(
              children: [
                Icon(_required ? LucideIcons.checkSquare : LucideIcons.square, size: 18, color: _required ? AppColors.gold : AppColors.mute),
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
                  onPressed: _title.text.trim().isEmpty || _body.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(WaiverDoc(
                            id: widget.initial?.id ?? "waiver-${DateTime.now().microsecondsSinceEpoch}",
                            title: _title.text.trim(),
                            body: _body.text,
                            scope: _scope,
                            planId: _scope == "plan" ? _planId : null,
                            required: _required,
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
            TextButton(onPressed: widget.onDelete, style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)), child: const Text("Delete document")),
          ],
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 12, color: selected ? AppColors.gold : AppColors.txt)),
      ),
    );
  }
}

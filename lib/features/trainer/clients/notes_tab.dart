import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/flag_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer_note.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

const _noteFlags = ["red", "yellow", "blue"];

/// Mirrors TrainerNotesTab.jsx — the coach flag/notes system for one client:
/// active notes grouped by flag priority, resolve/edit/archive actions, and
/// a collapsed history of resolved/archived notes.
class NotesTab extends ConsumerStatefulWidget {
  const NotesTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<NotesTab> {
  bool _adding = false;
  TrainerNote? _editing;
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    if (record == null) return const SizedBox.shrink();
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    final myName = isOwner ? "Owner" : (trainers.where((t) => t.id == trainerAuth).isNotEmpty ? trainers.firstWhere((t) => t.id == trainerAuth).name : "Coach");

    void mutateNotes(List<TrainerNote> Function(List<TrainerNote>) f) {
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(trainerNotes: f(r.trainerNotes)));
    }

    if (_adding || _editing != null) {
      return _NoteForm(
        initial: _editing,
        onCancel: () => setState(() {
          _adding = false;
          _editing = null;
        }),
        onSave: (flag, title, details, bodyArea, followUp, resolveBy) {
          if (_editing != null) {
            mutateNotes((notes) => notes
                .map((n) => n.id == _editing!.id
                    ? n.copyWith(flag: flag, title: title, details: details, bodyArea: bodyArea, followUpRequired: followUp, resolveBy: resolveBy, modifiedAt: _nowLabel())
                    : n)
                .toList());
          } else {
            mutateNotes((notes) => [
                  ...notes,
                  TrainerNote(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    flag: flag,
                    title: title,
                    details: details,
                    coachId: trainerAuth ?? "",
                    coachName: myName,
                    createdAt: _nowLabel(),
                    bodyArea: bodyArea,
                    followUpRequired: followUp,
                    resolveBy: resolveBy,
                  ),
                ]);
          }
          setState(() {
            _adding = false;
            _editing = null;
          });
        },
      );
    }

    final active = record.trainerNotes.where((n) => n.status == "active").toList();
    final history = record.trainerNotes.where((n) => n.status != "active").toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Trainer Notes"),
              TextButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text("Add Note", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          if (active.isEmpty) const HintBox(text: "No active notes for this client."),
          for (final flag in _noteFlags) ...[
            if (active.any((n) => n.flag == flag)) ...[
              _FlagHeader(flag: flag, count: active.where((n) => n.flag == flag).length),
              ...active.where((n) => n.flag == flag).map((n) => _NoteCard(
                    note: n,
                    canEdit: isOwner || n.coachId == trainerAuth,
                    isOwner: isOwner,
                    onEdit: () => setState(() => _editing = n),
                    onResolve: () => mutateNotes((notes) => notes.map((x) => x.id == n.id ? x.copyWith(status: "resolved", modifiedAt: _nowLabel()) : x).toList()),
                    onArchive: () => mutateNotes((notes) => notes.map((x) => x.id == n.id ? x.copyWith(status: "archived", modifiedAt: _nowLabel()) : x).toList()),
                    onDelete: () => mutateNotes((notes) => notes.where((x) => x.id != n.id).toList()),
                    onChangeFlag: (f) => mutateNotes((notes) => notes.map((x) => x.id == n.id ? x.copyWith(flag: f) : x).toList()),
                  )),
              const SizedBox(height: 6),
            ],
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => _showHistory = !_showHistory),
              style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero),
              child: Text("${_showHistory ? 'Hide' : 'Show'} resolved/archived (${history.length})", style: const TextStyle(fontSize: 12)),
            ),
            if (_showHistory)
              ...history.map((n) => Opacity(
                    opacity: 0.7,
                    child: AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(kFlagMeta[n.flag]!.emoji, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title?.isNotEmpty == true ? n.title! : n.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text("${n.status == 'resolved' ? 'Resolved' : 'Archived'} · by ${n.coachName}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                              ],
                            ),
                          ),
                          if (isOwner)
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => mutateNotes((notes) => notes.map((x) => x.id == n.id ? x.copyWith(status: "active", modifiedAt: _nowLabel()) : x).toList()),
                                  child: const Text("Restore", style: TextStyle(fontSize: 11)),
                                ),
                                IconButton(
                                  onPressed: () => mutateNotes((notes) => notes.where((x) => x.id != n.id).toList()),
                                  icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}

class _FlagHeader extends StatelessWidget {
  const _FlagHeader({required this.flag, required this.count});
  final String flag;
  final int count;

  @override
  Widget build(BuildContext context) {
    final m = kFlagMeta[flag]!;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Text("${m.shortLabel} ($count)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: m.color, letterSpacing: 0.5)),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.canEdit,
    required this.isOwner,
    required this.onEdit,
    required this.onResolve,
    required this.onArchive,
    required this.onDelete,
    required this.onChangeFlag,
  });

  final TrainerNote note;
  final bool canEdit;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onResolve;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final void Function(String) onChangeFlag;

  @override
  Widget build(BuildContext context) {
    final m = kFlagMeta[note.flag]!;
    return AppCard(
      borderColor: m.color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.title?.isNotEmpty == true) Text(note.title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (note.title?.isNotEmpty == true) const SizedBox(height: 4),
          Text(note.details, style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.4)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (note.bodyArea != null) Tag(text: note.bodyArea!),
            if (note.followUpRequired) const Tag(text: "Follow-up required", gold: true),
            if (note.resolveBy != null) Tag(text: "Resolve by ${note.resolveBy}"),
          ]),
          const SizedBox(height: 6),
          Text("by ${note.coachName} · ${note.createdAt}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: onResolve,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.grn, side: const BorderSide(color: AppColors.grn), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                child: const Text("Mark resolved", style: TextStyle(fontSize: 11)),
              ),
              if (canEdit)
                OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text("Edit", style: TextStyle(fontSize: 11)),
                ),
              if (isOwner) ...[
                DropdownButton<String>(
                  value: note.flag,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.card,
                  style: const TextStyle(fontSize: 11, color: AppColors.txt),
                  items: _noteFlags.map((f) => DropdownMenuItem(value: f, child: Text(kFlagMeta[f]!.label))).toList(),
                  onChanged: (v) => v != null ? onChangeFlag(v) : null,
                ),
                OutlinedButton(
                  onPressed: onArchive,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text("Archive", style: TextStyle(fontSize: 11)),
                ),
                OutlinedButton(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), side: const BorderSide(color: Color(0xFF8B3B3B)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text("Delete", style: TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({required this.initial, required this.onCancel, required this.onSave});
  final TrainerNote? initial;
  final VoidCallback onCancel;
  final void Function(String flag, String? title, String details, String? bodyArea, bool followUp, String? resolveBy) onSave;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late String _flag = widget.initial?.flag ?? "yellow";
  late final _title = TextEditingController(text: widget.initial?.title ?? "");
  late final _details = TextEditingController(text: widget.initial?.details ?? "");
  late String? _bodyArea = widget.initial?.bodyArea;
  late bool _followUp = widget.initial?.followUpRequired ?? false;
  late final _resolveBy = TextEditingController(text: widget.initial?.resolveBy ?? "");

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _resolveBy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Note" : "Add Note"),
          const SizedBox(height: 14),
          const Text("FLAG", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: _noteFlags.map((f) {
              final m = kFlagMeta[f]!;
              final selected = _flag == f;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _flag = f),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? m.color.withValues(alpha: 0.15) : AppColors.card,
                        border: Border.all(color: selected ? m.color : AppColors.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("${m.emoji} ${m.label}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? m.color : AppColors.mute)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          FieldLabeled(label: "Title (optional)", child: AppField(controller: _title)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Details", child: TextField(
            controller: _details,
            maxLines: 4,
            style: const TextStyle(color: AppColors.txt, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          )),
          const SizedBox(height: 10),
          const Text("BODY AREA (OPTIONAL)", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kBodyAreas.map((a) {
              final selected = _bodyArea == a;
              return InkWell(
                onTap: () => setState(() => _bodyArea = selected ? null : a),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
                    border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(a, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.mute)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          FieldLabeled(label: "Resolve by (optional, YYYY-MM-DD)", child: AppField(controller: _resolveBy)),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _followUp = !_followUp),
            child: Row(
              children: [
                Icon(_followUp ? LucideIcons.checkSquare : LucideIcons.square, size: 18, color: _followUp ? AppColors.gold : AppColors.mute),
                const SizedBox(width: 8),
                const Text("Follow-up required", style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _details.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(_flag, _title.text.trim().isEmpty ? null : _title.text.trim(), _details.text.trim(), _bodyArea, _followUp, _resolveBy.text.trim().isEmpty ? null : _resolveBy.text.trim()),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
        ],
      ),
    );
  }
}

String _nowLabel() {
  final d = DateTime.now();
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? "AM" : "PM";
  return "${months[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ampm";
}

import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";
import "../../../data/models/trainer.dart";
import "availability_block_editor.dart";

/// Mirrors TrainerForm.jsx, trimmed to the fields relevant without real
/// auth/2FA/Stripe: name/email/phone, location, availability blocks
/// (simplified single-tier editor — see AvailabilityBlockEditor), and an
/// owner-only commission rate. Photo crop, password/2FA, and the
/// approval-code self-signup gate are all out of scope for this mock build.
class TrainerEditForm extends StatefulWidget {
  const TrainerEditForm({super.key, required this.initial, required this.isOwnerEditing, required this.onCancel, required this.onSave, this.onDelete});

  final Trainer? initial;
  final bool isOwnerEditing; // whether commission rate + delete are shown
  final VoidCallback onCancel;
  final ValueChanged<Trainer> onSave;
  final VoidCallback? onDelete;

  @override
  State<TrainerEditForm> createState() => _TrainerEditFormState();
}

class _TrainerEditFormState extends State<TrainerEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late final _email = TextEditingController(text: widget.initial?.email ?? "");
  late final _phone = TextEditingController(text: widget.initial?.phone ?? "");
  late final _locationName = TextEditingController(text: widget.initial?.locationName ?? "ONE Fitness");
  late final _locationAddress = TextEditingController(text: widget.initial?.locationAddress ?? "");
  late final _commission = TextEditingController(text: "${widget.initial?.commissionRate ?? 0}");
  late List<AvailabilityBlock> _availability = [...(widget.initial?.availability ?? [])];
  bool _editingBlock = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _locationName.dispose();
    _locationAddress.dispose();
    _commission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editingBlock) {
      return AvailabilityBlockEditor(
        onCancel: () => setState(() => _editingBlock = false),
        onSave: (block) => setState(() {
          _availability = [..._availability, block];
          _editingBlock = false;
        }),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Trainer" : "New Trainer"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Full name", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Email", child: AppField(controller: _email, keyboardType: TextInputType.emailAddress)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Phone", child: AppField(controller: _phone, keyboardType: TextInputType.phone)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Location name", child: AppField(controller: _locationName)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Location address", child: AppField(controller: _locationAddress)),
          if (widget.isOwnerEditing) ...[
            const SizedBox(height: 10),
            FieldLabeled(label: "Commission rate (%)", child: AppField(controller: _commission, keyboardType: TextInputType.number)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("AVAILABILITY", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () => setState(() => _editingBlock = true),
                icon: const Icon(LucideIcons.plus, size: 13, color: AppColors.gold),
                label: const Text("Add block", style: TextStyle(color: AppColors.gold, fontSize: 12)),
              ),
            ],
          ),
          if (_availability.isEmpty) const HintBox(text: "No availability set yet."),
          ..._availability.asMap().entries.map((entry) {
            final i = entry.key;
            final b = entry.value;
            final slotCount = b.byDay.values.fold<int>(0, (m, l) => m + l.length);
            return AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${sessionTypeLabel(b.sessionType)} · ${disciplineLabel(b.discipline)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text("${b.byDay.length} day${b.byDay.length == 1 ? '' : 's'} · $slotCount slot${slotCount == 1 ? '' : 's'}/week", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => _availability = [..._availability]..removeAt(i)), icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B))),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => widget.onSave(Trainer(
                            id: widget.initial?.id ?? "trainer-${DateTime.now().microsecondsSinceEpoch}",
                            name: _name.text.trim(),
                            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                            locationName: _locationName.text.trim().isEmpty ? null : _locationName.text.trim(),
                            locationAddress: _locationAddress.text.trim().isEmpty ? null : _locationAddress.text.trim(),
                            commissionRate: num.tryParse(_commission.text.trim()) ?? (widget.initial?.commissionRate ?? 0),
                            availability: _availability,
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
            TextButton(onPressed: widget.onDelete, style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)), child: const Text("Remove trainer")),
          ],
        ],
      ),
    );
  }
}

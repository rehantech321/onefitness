import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "trainer_edit_form.dart";

/// Mirrors StaffManager.jsx (owner-only) — trainer roster with add/edit
/// in place of a modal.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  Trainer? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider);

    if (_editing != null || _creating) {
      return TrainerEditForm(
        initial: _editing,
        isOwnerEditing: true,
        onCancel: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        onSave: (t) async {
          // Creating a brand-new trainer needs a real Supabase Auth account
          // (sign-up), not just a row write — out of scope for now, so a
          // new trainer still only lands in local mock state.
          if (_editing != null) {
            try {
              await SupabaseService.updateTrainerRow(t.id, name: t.name, email: t.email, phone: t.phone, locationName: t.locationName, locationAddress: t.locationAddress, availability: t.availability);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
              }
              return;
            }
          }
          ref.read(trainersProvider.notifier).upsert(t);
          setState(() {
            _editing = null;
            _creating = false;
          });
        },
        onDelete: _editing == null
            ? null
            : () {
                ref.read(trainersProvider.notifier).remove(_editing!.id);
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
              SectionLabel("Trainers (${trainers.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text("Trainer", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          ...trainers.map((t) {
            final disciplines = t.availability.map((b) => b.discipline).toSet();
            final sessionTypes = t.availability.map((b) => b.sessionType).toSet();
            return AppCard(
              onTap: () => setState(() => _editing = t),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(name: t.name, size: 40),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      const Icon(LucideIcons.edit3, size: 15, color: AppColors.mute),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 5, runSpacing: 5, children: [...sessionTypes.map((s) => Tag(text: sessionTypeLabel(s), gold: true)), ...disciplines.map((d) => Tag(text: disciplineLabel(d)))]),
                  const SizedBox(height: 10),
                  if (t.email != null) _IconLine(icon: LucideIcons.mail, text: t.email!),
                  if (t.phone != null) _IconLine(icon: LucideIcons.phone, text: t.phone!),
                  if (t.locationName != null) _IconLine(icon: LucideIcons.mapPin, text: t.locationName!),
                  _IconLine(icon: LucideIcons.percent, text: "${t.commissionRate}% commission"),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.mute),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
        ],
      ),
    );
  }
}

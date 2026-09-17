import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// The gym's equipment list — what the exercise form offers as a picker.
/// Staff add here or inline while adding an exercise; only the owner can
/// remove, since a removed name silently disappears from the picker for
/// every coach.
class EquipmentLibraryScreen extends ConsumerStatefulWidget {
  const EquipmentLibraryScreen({super.key});

  @override
  ConsumerState<EquipmentLibraryScreen> createState() => _EquipmentLibraryScreenState();
}

class _EquipmentLibraryScreenState extends ConsumerState<EquipmentLibraryScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final existing = ref.read(equipmentProvider);
    final clash = existing.where((e) => e.toLowerCase() == name.toLowerCase());
    if (clash.isNotEmpty) {
      setState(() => _error = '"${clash.first}" is already in the library.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.insertEquipment(name);
      ref.read(equipmentProvider.notifier).add(name);
      _name.clear();
    } catch (e) {
      setState(() => _error = "Couldn't add that — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String name) async {
    // How many catalogue exercises reference it — deleting still goes
    // ahead (those exercises keep the text), but the owner should know.
    final used = ref.read(exerciseCatalogProvider).where((e) => e.equipment.any((q) => q.toLowerCase() == name.toLowerCase())).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Remove "$name"?'),
        content: Text(
          used == 0
              ? "It stops being offered when adding exercises. Nothing else changes."
              : "$used exercise${used == 1 ? '' : 's'} list${used == 1 ? 's' : ''} it. They keep the name; it just stops being offered for new exercises.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.deleteEquipment(name);
      ref.read(equipmentProvider.notifier).remove(name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't remove that — check your connection and try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(equipmentProvider);
    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    final q = _search.text.trim().toLowerCase();
    final visible = all.where((e) => q.isEmpty || e.toLowerCase().contains(q)).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel("Equipment Library"),
          const SizedBox(height: 4),
          const Text(
            "Everything the gym has. When you add an exercise, its equipment is picked from this list — and anything typed there is added here too.",
            style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Add equipment", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppField(
                        controller: _name,
                        placeholder: "e.g. Kettlebell 16kg",
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    BtnGold(onPressed: _busy ? null : _add, child: Text(_busy ? "Adding…" : "Add")),
                  ],
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.errorText))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppField(controller: _search, placeholder: "Search equipment…", onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          if (all.isEmpty)
            const HintBox(text: "No equipment yet — add the first item above.")
          else if (visible.isEmpty)
            const HintBox(text: "Nothing matches that search.")
          else
            for (final name in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.dumbbell, size: 15, color: AppColors.gold),
                      const SizedBox(width: 10),
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      if (isOwner)
                        IconButton(
                          onPressed: () => _delete(name),
                          icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.errorText),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Text(
            "${all.length} item${all.length == 1 ? '' : 's'} in the library",
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "trainer_edit_form.dart";

/// A coach editing their own profile (App.jsx trainerMode "myprofile") —
/// same form as Staff management, minus commission rate and delete.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final trainers = ref.watch(trainersProvider);
    final matches = trainers.where((t) => t.id == trainerAuth);
    if (matches.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "Profile not found."));

    return TrainerEditForm(
      initial: matches.first,
      isOwnerEditing: false,
      onCancel: () {},
      onSave: (t) async {
        try {
          await SupabaseService.updateTrainerRow(
            t.id,
            name: t.name,
            email: t.email,
            phone: t.phone,
            photo: t.photo,
            disciplines: t.disciplines,
            sessionTypes: t.sessionTypes,
            locations: t.locations,
            bio: t.bio ?? "",
            beforeAfters: t.beforeAfters,
            availability: t.availability,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
          }
          return;
        }
        ref.read(trainersProvider.notifier).upsert(t);
      },
    );
  }
}

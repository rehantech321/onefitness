import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
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
      onSave: (t) => ref.read(trainersProvider.notifier).upsert(t),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/legal/terms_screen.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/delete_account_screen.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../shell/trainer_shell_state.dart";
import "trainer_edit_form.dart";

/// A coach editing their own profile (App.jsx trainerMode "myprofile") —
/// same form as Staff management, minus commission rate and delete-someone-
/// else, plus the coach's own Account section: the Terms they agreed to,
/// and deleting their own account (Apple guideline 5.1.1(v), which applies
/// to every account-holding role, not just clients).
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  /// null = the profile form; otherwise "terms" or "delete".
  String? _section;

  void _close() => setState(() => _section = null);

  @override
  Widget build(BuildContext context) {
    if (_section == "terms") {
      return LocalBackScope(
        isOpen: true,
        onBack: _close,
        child: TermsScreen(onBack: _close),
      );
    }
    if (_section == "delete") {
      return LocalBackScope(
        isOpen: true,
        onBack: _close,
        child: DeleteAccountScreen(
          isCoach: true,
          onBack: _close,
          onDeleted: () {
            ref.read(accountDeletedNoticeProvider.notifier).show();
            ref.read(trainerAuthProvider.notifier).signOut();
          },
        ),
      );
    }

    final trainerAuth = ref.watch(trainerAuthProvider);
    final trainers = ref.watch(trainersProvider);
    final matches = trainers.where((t) => t.id == trainerAuth);
    if (matches.isEmpty) {
      return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "Profile not found."));
    }

    return Column(
      children: [
        Expanded(
          child: TrainerEditForm(
            initial: matches.first,
            isOwnerEditing: false,
            onCancel: () => ref.read(trainerModeProvider.notifier).goBack(),
            onSave: (t, password) async {
              try {
                await SupabaseService.updateTrainerRow(
                  t.id,
                  name: t.name,
                  title: t.title,
                  email: t.email,
                  phone: t.phone,
                  photo: t.photo,
                  disciplines: t.disciplines,
                  sessionTypes: t.sessionTypes,
                  locations: t.locations,
                  bio: t.bio ?? "",
                  beforeAfters: t.beforeAfters,
                  availability: t.availability,
                  unavailability: t.unavailability,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Couldn't save — check your connection and try again.")),
                  );
                }
                return;
              }
              ref.read(trainersProvider.notifier).upsert(t);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✓ Profile saved")),
                );
              }
              ref.read(trainerModeProvider.notifier).goBack();
            },
          ),
        ),
        // Pinned below the form so it's reachable without saving first, and
        // stays two taps from the menu: Menu -> My Profile -> Delete Account.
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(() => _section = "terms"),
                  style: TextButton.styleFrom(foregroundColor: AppColors.mute),
                  icon: const Icon(LucideIcons.fileText, size: 15),
                  label: const Text("Terms of Use", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(() => _section = "delete"),
                  style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
                  icon: const Icon(LucideIcons.trash2, size: 15),
                  label: const Text("Delete Account", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

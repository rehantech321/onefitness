import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/intake/intake_area_screen.dart";

/// Coach-side entry point into a client's intake forms — reached only via
/// Profile tab's "Complete their onboarding" rows (ProfileTab.onGoToIntake),
/// there's no visible tab button for this (mirrors TrainerView.jsx: "intake"
/// isn't in PRIMARY/MORE_TABS either, only reachable the same way).
class IntakeTab extends ConsumerWidget {
  const IntakeTab({super.key, required this.clientId, this.initialOpenKey});

  final String clientId;
  final String? initialOpenKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(trainerClientRecordsProvider)[clientId];
    if (record == null) return const SizedBox.shrink();
    return IntakeAreaScreen(
      profileId: clientId,
      client: record,
      who: "trainer",
      initialOpenKey: initialOpenKey,
      onSaved: (key, rec) => ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(intake: {...r.intake, key: rec})),
    );
  }
}

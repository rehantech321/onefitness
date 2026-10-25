import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/intake/intake_area_screen.dart";

/// Coach-side entry point into a client's intake forms — reached from the
/// "Assessments" entry in TrainerView's More menu, or by tapping a row in the
/// Profile tab's "Complete their onboarding" summary (ProfileTab.onGoToIntake).
///
/// A coach opening an assessment the client has already completed lands on
/// their saved answers rather than on an editable form; see
/// IntakeAnswersScreen for why that matters.
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

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";
import "roster_bar.dart";
import "trainer_view.dart";

/// Mirrors the "Clients" section of App.jsx: RosterBar up top to pick a
/// client, TrainerView below for whichever one is active.
class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(selectedClientIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RosterBar(),
        Expanded(
          child: activeId == null
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: HintBox(text: "Select a client above to view their profile."),
                )
              : TrainerView(key: ValueKey(activeId), clientId: activeId),
        ),
      ],
    );
  }
}

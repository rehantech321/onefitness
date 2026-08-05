import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/theme/app_colors.dart";
import "core/theme/app_theme.dart";
import "data/providers/client_providers.dart";
import "data/providers/role_provider.dart";
import "data/providers/trainer_providers.dart";
import "features/auth/client_auth_screen.dart";
import "features/client/shell/client_shell.dart";
import "features/shell/app_header.dart";
import "features/trainer/auth/trainer_auth_screen.dart";
import "features/trainer/shell/trainer_shell.dart";

void main() {
  runApp(const ProviderScope(child: OneFitnessApp()));
}

class OneFitnessApp extends StatelessWidget {
  const OneFitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ONE Fitness",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _RootGate(),
    );
  }
}

/// Mirrors App.jsx's top-level structure: the Coach/Client pill toggle
/// (Header) above whichever shell is active, hidden once a client is signed
/// in. Each side's own auth screen gates its own shell independently.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final clientSignedIn = ref.watch(clientSignedInProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);

    final staffSignedIn = role == "trainer" && trainerAuth != null;
    final showHeader = !((role == "client" && clientSignedIn) || staffSignedIn);
    final body = role == "trainer" ? (trainerAuth == null ? const TrainerAuthScreen() : const TrainerShell()) : (clientSignedIn ? const ClientShell() : const ClientAuthScreen());

    if (!showHeader) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(child: body),
        ],
      ),
    );
  }
}

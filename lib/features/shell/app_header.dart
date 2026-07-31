import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/theme/app_colors.dart";
import "../../data/providers/role_provider.dart";
import "../../data/providers/trainer_providers.dart";

/// Mirrors AppShell.jsx's `Header` — the Coach/Client pill toggle shown
/// above whichever shell is active, plus the ONE Fitness logo once a coach
/// is signed in. Hidden entirely once a client is signed in (their shell
/// takes the full screen), matching the source's
/// `!(role === "client" && activeClient)` condition. The pill itself is
/// only useful for picking which login form to show, so once staff
/// (coach or owner) are actually signed in it drops away too, leaving just
/// the logo.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);
    final staffSignedIn = role == "trainer" && trainerAuth != null;

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              if (staffSignedIn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.asset("assets/images/logo.png", height: 26),
                ),
              if (!staffSignedIn)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(50), border: Border.all(color: AppColors.line)),
                  child: Row(
                    children: [
                      _PillButton(label: "Coach", selected: role == "trainer", onTap: () => ref.read(roleProvider.notifier).set("trainer")),
                      _PillButton(label: "Client", selected: role == "client", onTap: () => ref.read(roleProvider.notifier).set("client")),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? AppColors.gold : Colors.transparent, borderRadius: BorderRadius.circular(50)),
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.3, color: selected ? Colors.white : AppColors.mute),
          ),
        ),
      ),
    );
  }
}

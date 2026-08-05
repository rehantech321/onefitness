import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/theme/app_colors.dart";
import "../../data/providers/role_provider.dart";

/// Mirrors AppShell.jsx's `Header` — the Coach/Client pill toggle used to
/// pick which sign-in form to show. Hidden entirely once someone is
/// actually signed in (client or staff) — their own shell takes the full
/// screen with no reserved space above it, matching the source's
/// `!(role === "client" && activeClient)` condition, extended the same way
/// for the staff side.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(50), border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                _PillButton(label: "Coach", selected: role == "trainer", onTap: () => ref.read(roleProvider.notifier).set("trainer")),
                _PillButton(label: "Client", selected: role == "client", onTap: () => ref.read(roleProvider.notifier).set("client")),
              ],
            ),
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

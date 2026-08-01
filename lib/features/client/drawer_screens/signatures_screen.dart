import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors SignaturesScreen.jsx — the client's signed waivers/contracts log.
class SignaturesScreen extends ConsumerWidget {
  const SignaturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientRecordProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Signed Documents"),
          if (client.signatures.isEmpty)
            const HintBox(
              text: "Waivers and contracts you've signed will appear here once ONE Fitness adds them — nothing's required of you yet.",
            )
          else
            ...client.signatures.map((s) => AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.fileSignature, size: 17, color: AppColors.gold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text("Signed ${s.signedAt}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.check, size: 16, color: AppColors.grn),
                        ],
                      ),
                      if (s.summary != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(s.summary!, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
                        ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

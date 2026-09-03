import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/merge_token_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "waiver_signing_screen.dart";

/// Mirrors SignaturesScreen.jsx — the client's signed waivers/contracts
/// log, plus (Variable & Signature Capture spec) an "outstanding" section
/// listing whatever the client still needs to sign, since a document
/// they've never seen can't very well appear in their own signed-docs list.
class SignaturesScreen extends ConsumerStatefulWidget {
  const SignaturesScreen({super.key});

  @override
  ConsumerState<SignaturesScreen> createState() => _SignaturesScreenState();
}

class _SignaturesScreenState extends ConsumerState<SignaturesScreen> {
  WaiverDoc? _signing;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final info = ref.watch(clientInfoProvider);
    final allDocs = ref.watch(waiversProvider);
    final outstanding = outstandingWaivers(allDocs: allDocs, signatures: client.signatures, clientPlanId: info.membershipPlanId);

    if (_signing != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _signing = null),
        child: WaiverSigningScreen(doc: _signing!, onBack: () => setState(() => _signing = null)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outstanding.isNotEmpty) ...[
            SectionLabel("Needs Your Signature (${outstanding.length})"),
            ...outstanding.map((d) => AppCard(
                  borderColor: AppColors.gold,
                  onTap: () => setState(() => _signing = d),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.fileSignature, size: 17, color: AppColors.gold),
                      const SizedBox(width: 10),
                      Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.gold),
                    ],
                  ),
                )),
            const SizedBox(height: 10),
          ],
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

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/merge_token_utils.dart";
import "../../../core/widgets/signed_waiver_tile.dart";
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
  const SignaturesScreen({super.key, this.onGoBooking, this.openDocId, this.onOpened});

  /// Where the client lands once they've signed — Booking, since signing is
  /// what stood between them and booking a session.
  final VoidCallback? onGoBooking;

  /// Open this waiver straight away instead of showing the list.
  ///
  /// Set when the client has already said they want to sign — from the
  /// "Sign now" prompt, say — so they aren't put in front of a list and
  /// asked to find the document they just agreed to.
  final String? openDocId;

  /// Told once [openDocId] has been acted on, so the caller can forget it.
  /// Without this the request would outlive the trip that made it and the
  /// waiver would spring open again on a later visit — including after it
  /// had been signed.
  final VoidCallback? onOpened;

  @override
  ConsumerState<SignaturesScreen> createState() => _SignaturesScreenState();
}

class _SignaturesScreenState extends ConsumerState<SignaturesScreen> {
  WaiverDoc? _signing;

  /// Set once, on arrival, when the caller asked for a particular waiver to
  /// be opened — the "Sign now" prompt does, because landing someone on a
  /// list after they've just said yes makes them hunt for the thing they
  /// already agreed to do.
  bool _openedRequested = false;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final info = ref.watch(clientInfoProvider);
    final allDocs = ref.watch(waiversProvider);
    final outstanding = outstandingWaivers(allDocs: allDocs, signatures: client.signatures, clientPlanIds: info.heldPlanIds);

    // Opening it here rather than in initState: the waiver list is loaded
    // with everything else, so on a cold start it can still be empty when
    // this screen is first built. Waiting for it to arrive means "Sign now"
    // works whether the data was ready or not.
    if (!_openedRequested && _signing == null) {
      final wanted = widget.openDocId;
      if (wanted != null) {
        final match = allDocs.where((d) => d.id == wanted);
        if (match.isNotEmpty) {
          _openedRequested = true;
          _signing = match.first;
          // After this frame: the caller clearing it now would rebuild the
          // tree we are in the middle of building.
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOpened?.call());
        } else if (allDocs.isNotEmpty) {
          // The list arrived and that document isn't in it — it was
          // archived or deleted between the prompt and here. Stop waiting
          // and show the list rather than hanging on a document that is
          // never coming.
          _openedRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOpened?.call());
        }
      }
    }

    if (_signing != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _signing = null),
        child: WaiverSigningScreen(
          doc: _signing!,
          onBack: () => setState(() => _signing = null),
          // Straight to Booking once it's signed — that's what they were
          // being kept from. Falls back to this list if Booking isn't
          // reachable from here.
          onDone: widget.onGoBooking == null
              ? null
              : () {
                  setState(() => _signing = null);
                  widget.onGoBooking!();
                },
          doneLabel: widget.onGoBooking == null ? "Done" : "Go to Booking",
        ),
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
            ...client.signatures.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SignedWaiverTile(
                    signatureId: s.id,
                    title: s.title,
                    subtitle: "Signed ${s.signedAt}",
                    detail: s.summary,
                  ),
                )),
        ],
      ),
    );
  }
}

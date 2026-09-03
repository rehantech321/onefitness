import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/merge_token_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/signature.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";
import "../shell/client_shell_state.dart";

/// Variable & Signature Capture spec — the real signing flow behind
/// SignaturesScreen's "Sign" action: renders [doc].body with every
/// `{{token}}` resolved, walks each `{{initial}}` in order requiring its
/// own confirm tap, the final `{{signature}}`, a guardian block if the
/// client is a minor, an optional photo/video opt-out, the separate
/// electronic-signing consent acknowledgment, then submits everything to
/// sign-waiver (server-side — see that function for why the audit fields
/// can't just be trusted from here).
class WaiverSigningScreen extends ConsumerStatefulWidget {
  const WaiverSigningScreen({super.key, required this.doc, required this.onBack});

  final WaiverDoc doc;
  final VoidCallback onBack;

  @override
  ConsumerState<WaiverSigningScreen> createState() => _WaiverSigningScreenState();
}

class _WaiverSigningScreenState extends ConsumerState<WaiverSigningScreen> {
  late List<String?> _initials;
  String? _signatureImage;
  String? _guardianSignatureImage;
  late final TextEditingController _guardianNameController;
  bool? _photoOptOut;
  bool _consentChecked = false;
  bool _busy = false;
  String? _error;
  SignedDocument? _result;

  @override
  void initState() {
    super.initState();
    final info = ref.read(clientInfoProvider);
    final record = ref.read(clientRecordProvider);
    final tokenValues = buildMergeTokenValues(info: info, record: record);
    final resolved = resolveMergeTokens(widget.doc.body, tokenValues);
    _initials = List<String?>.filled(countInitialSegments(resolved), null);
    _guardianNameController = TextEditingController(text: record.guardianName ?? "");
  }

  @override
  void dispose() {
    _guardianNameController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool isMinor, required int totalInitials}) async {
    final info = ref.read(clientInfoProvider);
    final missingInitial = _initials.any((i) => i == null);
    if (missingInitial || _signatureImage == null || !_consentChecked || (isMinor && (_guardianNameController.text.trim().isEmpty || _guardianSignatureImage == null))) {
      setState(() => _error = "Please complete every initial, the signature, and the consent checkbox before submitting.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = Platform.isAndroid || Platform.isIOS ? "${Platform.operatingSystem} ${Platform.operatingSystemVersion}" : Platform.operatingSystem;
      final signed = await SupabaseService.signWaiver(
        clientId: info.id,
        waiverId: widget.doc.id,
        initialsImages: _initials.whereType<String>().toList(),
        signatureImage: _signatureImage!,
        guardianName: isMinor ? _guardianNameController.text.trim() : null,
        guardianSignatureImage: isMinor ? _guardianSignatureImage : null,
        photoOptOut: _photoOptOut,
        consentAcknowledged: _consentChecked,
        deviceInfo: device,
        adoptSignature: true,
        adoptInitials: true,
      );
      ref.read(clientRecordProvider.notifier).update(
            (record) => record.copyWith(
              signatures: [...record.signatures.where((s) => s.docId != widget.doc.id), signed],
              adoptedSignatureImage: _signatureImage,
              adoptedInitialsImage: _initials.first,
              guardianName: isMinor ? _guardianNameController.text.trim() : record.guardianName,
              photoVideoOptOut: _photoOptOut ?? record.photoVideoOptOut,
            ),
          );
      if (mounted) setState(() => _result = signed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final record = ref.watch(clientRecordProvider);
    final trainers = ref.watch(trainersProvider);
    final coachMatches = trainers.where((t) => t.id == info.primaryTrainerId);
    final coach = coachMatches.isEmpty ? null : coachMatches.first;

    if (!hasRequiredContactInfo(record)) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackRow(onBack: widget.onBack),
            const SizedBox(height: 8),
            SectionLabel(widget.doc.title),
            const SizedBox(height: 8),
            const HintBox(
              text: "We need an emergency contact on file before you can sign this document. Complete the Emergency Contact section of your Personalized Training Intake, then come back here.",
            ),
            const SizedBox(height: 12),
            BtnGold(
              onPressed: () => ref.read(clientScreenProvider.notifier).go("forms"),
              child: const Text("Go to Assessments"),
            ),
          ],
        ),
      );
    }

    if (_result != null) {
      final s = _result!;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel("Signed — ${widget.doc.title}"),
            const SizedBox(height: 8),
            AppCard(
              borderColor: AppColors.gold,
              child: Row(
                children: [
                  const Icon(LucideIcons.checkCircle2, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(child: Text("Signed ${s.signedAt}. A copy is available below and was added to your Signatures list.", style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
            if (s.pdfDataUrl != null) ...[
              const SizedBox(height: 8),
              DownloadPdfButton(filename: "${widget.doc.title}.pdf", pdfDataUrl: s.pdfDataUrl!),
            ],
            const SizedBox(height: 16),
            BtnGhost(onPressed: widget.onBack, child: const Text("Done")),
          ],
        ),
      );
    }

    final tokenValues = buildMergeTokenValues(info: info, record: record, coach: coach);
    final resolved = resolveMergeTokens(widget.doc.body, tokenValues);
    final segments = parseWaiverSegments(resolved);
    final totalInitials = countInitialSegments(resolved);
    final age = ageFromBirthday(info.birthday);
    final isMinor = age != null && age < 18;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackRow(onBack: widget.onBack),
          const SizedBox(height: 8),
          SectionLabel(widget.doc.title),
          const SizedBox(height: 10),
          ...segments.map((seg) => switch (seg) {
                WaiverTextSegment(:final text) => _WaiverText(text: text),
                WaiverInitialSegment(:final index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _CaptureBlock(
                      label: "Initial here ($index of $totalInitials)",
                      adoptedImage: record.adoptedInitialsImage,
                      height: 70,
                      onCaptured: (img) => setState(() => _initials[index - 1] = img),
                    ),
                  ),
                WaiverSignatureSegment() => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _CaptureBlock(
                      label: "Client Signature",
                      adoptedImage: record.adoptedSignatureImage,
                      onCaptured: (img) => setState(() => _signatureImage = img),
                    ),
                  ),
                WaiverGuardianSignatureSegment() when isMinor => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Parent/Legal Guardian Name", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                        const SizedBox(height: 4),
                        AppField(controller: _guardianNameController),
                        const SizedBox(height: 10),
                        _CaptureBlock(
                          label: "Guardian Signature",
                          adoptedImage: null,
                          onCaptured: (img) => setState(() => _guardianSignatureImage = img),
                        ),
                      ],
                    ),
                  ),
                WaiverGuardianSignatureSegment() => const SizedBox.shrink(),
                WaiverPhotoOptOutSegment() => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: CheckboxListTile(
                      value: _photoOptOut ?? false,
                      onChanged: (v) => setState(() => _photoOptOut = v),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text("I decline photo/video permission.", style: TextStyle(fontSize: 13)),
                    ),
                  ),
              }),
          const SizedBox(height: 8),
          AppCard(
            child: CheckboxListTile(
              value: _consentChecked,
              onChanged: (v) => setState(() => _consentChecked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text("I agree to sign this document electronically.", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          BtnGold(
            full: true,
            onPressed: _busy ? null : () => _submit(isMinor: isMinor, totalInitials: totalInitials),
            child: Text(_busy ? "Submitting…" : "Submit"),
          ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onBack,
        style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(LucideIcons.chevronLeft, size: 18),
        label: const Text("Back", style: TextStyle(fontSize: 13)),
      );
}

/// Renders a plain-text chunk of a waiver body with the same lightweight
/// `**bold**` / `*italic*` / `- bullet` convention manage_waivers_screen.dart's
/// editor toolbar writes — this is the first place that markup is actually
/// interpreted rather than just inserted.
class _WaiverText extends StatelessWidget {
  const _WaiverText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split("\n").where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final bullet = line.trimLeft().startsWith("- ");
          final content = bullet ? line.trimLeft().substring(2) : line;
          return Padding(
            padding: EdgeInsets.only(bottom: 4, left: bullet ? 12 : 0),
            child: Text.rich(_richify(bullet ? "•  $content" : content), style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.txt)),
          );
        }).toList(),
      ),
    );
  }

  TextSpan _richify(String s) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r"\*\*(.+?)\*\*|\*(.+?)\*");
    var last = 0;
    for (final m in pattern.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      final bold = m.group(1);
      if (bold != null) {
        spans.add(TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w800)));
      } else {
        spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return TextSpan(children: spans);
  }
}

/// One initial/signature capture point — shows the adopted image with a
/// one-tap "Confirm" (still its own timestamped consent action, never
/// silently auto-applied) plus "Use a different one" to redraw, or the
/// draw/type pad directly when there's nothing adopted yet.
class _CaptureBlock extends StatefulWidget {
  const _CaptureBlock({required this.label, required this.adoptedImage, required this.onCaptured, this.height = 100});
  final String label;
  final String? adoptedImage;
  final ValueChanged<String?> onCaptured;
  final double height;

  @override
  State<_CaptureBlock> createState() => _CaptureBlockState();
}

class _CaptureBlockState extends State<_CaptureBlock> {
  bool _drawingFresh = false;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final adopted = widget.adoptedImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (adopted != null && !_drawingFresh)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdoptedSignaturePreview(
                imageDataUrl: adopted,
                height: widget.height,
                onChange: () => setState(() {
                  _drawingFresh = true;
                  _confirmed = false;
                  widget.onCaptured(null);
                }),
              ),
              const SizedBox(height: 6),
              if (!_confirmed)
                BtnGhost(
                  onPressed: () {
                    setState(() => _confirmed = true);
                    widget.onCaptured(adopted);
                  },
                  child: const Text("Tap to confirm"),
                )
              else
                const Row(
                  children: [
                    Icon(LucideIcons.checkCircle2, size: 15, color: AppColors.gold),
                    SizedBox(width: 6),
                    Text("Confirmed", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700)),
                  ],
                ),
            ],
          )
        else
          SignaturePad(height: widget.height, onCaptured: widget.onCaptured),
      ],
    );
  }
}

import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/merge_token_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";

/// Signing a waiver: read the document, initial each of the five clauses,
/// tick the electronic-signing consent, then sign — or, for a client under
/// 18, a parent/guardian signs instead. Everything is submitted to the
/// sign-waiver server function, which records the audit trail, builds the
/// signed PDF, emails it to the client and stores it where both the client
/// and the owner can open it.
///
/// Initials follow "adopt once, confirm each": the client draws (or uses
/// their saved) initials in the first box; the other four show that same
/// image, but each one still needs its own tap, and each tap is its own
/// timestamped acknowledgement. Nothing is applied without an action.
class WaiverSigningScreen extends ConsumerStatefulWidget {
  const WaiverSigningScreen({super.key, required this.doc, required this.onBack, this.onDone, this.doneLabel = "Done"});

  final WaiverDoc doc;
  final VoidCallback onBack;

  /// What the final button does once signed — defaults to [onBack]. The
  /// booking flow uses it to carry straight on with the session being booked.
  final VoidCallback? onDone;
  final String doneLabel;

  @override
  ConsumerState<WaiverSigningScreen> createState() => _WaiverSigningScreenState();
}

class _WaiverSigningScreenState extends ConsumerState<WaiverSigningScreen> {
  // Initials — the image adopted in box 1, then one acknowledgement time per clause.
  String? _initials;
  String _initialsMethod = "draw";
  final List<String?> _acks = List<String?>.filled(kWaiverClauses.length, null);

  // Final signature (client) or guardian's.
  String? _signature;
  String _signatureMethod = "draw";
  String? _signatureAt;
  late final TextEditingController _guardianName;

  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;

  bool _photoRelease = false;
  String? _consentAt;

  bool _busy = false;
  String? _error;
  ({String id, String title, String? emailedTo})? _done;
  String? _pdfDataUrl;

  List<bool> get _sectionAckFlags => [for (final a in _acks) a != null];
  bool get _allInitialled => _sectionAckFlags.every((f) => f);

  @override
  void initState() {
    super.initState();
    final record = ref.read(clientRecordProvider);
    final answers = record.intake["personalTraining"]?.answers;
    _ecName = TextEditingController(text: answers?["ecName"]?.toString() ?? "");
    _ecPhone = TextEditingController(text: answers?["ecPhone"]?.toString() ?? "");
    _guardianName = TextEditingController(text: record.guardianName ?? "");
  }

  @override
  void dispose() {
    _ecName.dispose();
    _ecPhone.dispose();
    _guardianName.dispose();
    super.dispose();
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  void _adoptInitials(String image, String method) => setState(() {
        _initials = image;
        _initialsMethod = method;
        // Drawing or choosing the initials in box 1 IS the first clause's
        // acknowledgement.
        _acks[0] = _now();
      });

  void _clearInitials() => setState(() {
        _initials = null;
        // New initials mean every clause has to be re-acknowledged with them.
        for (var i = 0; i < _acks.length; i++) {
          _acks[i] = null;
        }
        _signature = null;
        _signatureAt = null;
      });

  Future<void> _submit({required bool isMinor}) async {
    if (_busy) return;
    final problems = <String>[
      if (_ecName.text.trim().isEmpty || _ecPhone.text.trim().isEmpty) "an emergency contact",
      if (!_allInitialled) "all five initials",
      if (isMinor && _guardianName.text.trim().isEmpty) "the guardian's name",
      if (_signature == null) isMinor ? "the guardian's signature" : "your signature",
      if (_consentAt == null) "the electronic-signing consent",
    ];
    if (problems.isNotEmpty) {
      setState(() => _error = "Still needed: ${problems.join(", ")}.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = "${Platform.operatingSystem} ${Platform.operatingSystemVersion}";
      final result = await SupabaseService.signWaiver(
        waiverId: widget.doc.id,
        sections: [
          for (var i = 0; i < kWaiverClauses.length; i++)
            {"key": kWaiverClauses[i].key, "image": _initials, "ackAt": _acks[i], "method": i == 0 ? _initialsMethod : "confirm"},
        ],
        signatureImage: isMinor ? null : _signature,
        signatureMethod: _signatureMethod,
        signatureAt: isMinor ? null : _signatureAt,
        guardianName: isMinor ? _guardianName.text.trim() : null,
        guardianSignatureImage: isMinor ? _signature : null,
        guardianSignedAt: isMinor ? _signatureAt : null,
        photoVideoRelease: _photoRelease,
        consentAt: _consentAt!,
        deviceInfo: device,
        emergencyContactName: _ecName.text.trim(),
        emergencyContactPhone: _ecPhone.text.trim(),
      );
      ref.read(clientRecordProvider.notifier).update(
            (r) => r.copyWith(
              signatures: [...r.signatures.where((s) => s.docId != widget.doc.id), result.summary],
              adoptedInitialsImage: _initials,
              adoptedSignatureImage: isMinor ? r.adoptedSignatureImage : _signature,
              guardianName: isMinor ? _guardianName.text.trim() : r.guardianName,
              photoVideoOptOut: !_photoRelease,
            ),
          );
      if (!mounted) return;
      setState(() => _done = (id: result.summary.id, title: result.summary.title, emailedTo: result.emailedTo));
      final pdf = await SupabaseService.loadWaiverSignaturePdf(result.summary.id);
      if (mounted) setState(() => _pdfDataUrl = pdf);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) return _buildDone(done);

    final info = ref.watch(clientInfoProvider);
    final record = ref.watch(clientRecordProvider);
    final trainers = ref.watch(trainersProvider);
    final coach = trainers.where((t) => t.id == info.primaryTrainerId).firstOrNull;
    final values = buildMergeTokenValues(info: info, record: record, coach: coach);
    final text = readableWaiverText(widget.doc.body, values);
    final age = ageFromBirthday(info.birthday);
    final isMinor = age != null && age < 18;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar(onBack: widget.onBack, title: widget.doc.title),
          const SizedBox(height: 10),

          // 1 — Read
          const _StepLabel(n: 1, text: "Read the document"),
          AppCard(child: _WaiverText(text: text)),
          const SizedBox(height: 16),

          // 2 — Emergency contact
          const _StepLabel(n: 2, text: "Emergency contact"),
          Row(
            children: [
              Expanded(child: FieldLabeled(label: "Name", child: AppField(controller: _ecName, onChanged: (_) => setState(() {})))),
              const SizedBox(width: 8),
              Expanded(child: FieldLabeled(label: "Phone", child: AppField(controller: _ecPhone, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {})))),
            ],
          ),
          const SizedBox(height: 16),

          // 3 — Initial each clause
          _StepLabel(n: 3, text: "Initial each section (${_sectionAckFlags.where((f) => f).length} of ${kWaiverClauses.length})"),
          for (var i = 0; i < kWaiverClauses.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ClauseCard(
                index: i,
                clause: kWaiverClauses[i],
                initials: _initials,
                savedInitials: record.adoptedInitialsImage,
                ackAt: _acks[i],
                onAdopt: i == 0 ? _adoptInitials : null,
                onConfirm: i == 0 || _initials == null ? null : () => setState(() => _acks[i] = _now()),
                onClear: i == 0 && _initials != null ? _clearInitials : null,
              ),
            ),
          const SizedBox(height: 6),

          // 4 — Choices and consent
          const _StepLabel(n: 4, text: "Your choices"),
          AppCard(
            child: Column(
              children: [
                CheckboxListTile(
                  value: _photoRelease,
                  onChanged: (v) => setState(() => _photoRelease = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Photo/Video Release", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: const Text("I allow ONE Fitness to use photos or video of me in its marketing. Leave unticked to opt out.", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                ),
                const Divider(color: AppColors.line, height: 12),
                CheckboxListTile(
                  value: _consentAt != null,
                  onChanged: (v) => setState(() => _consentAt = v == true ? _now() : null),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text("I agree to sign this document electronically", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: const Text("My electronic signature has the same legal effect as a handwritten one.", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5 — Sign (locked until every clause is initialled)
          _StepLabel(n: 5, text: isMinor ? "Parent / guardian signature" : "Sign"),
          if (!_allInitialled)
            const HintBox(text: "Initial all five sections above to unlock the signature.")
          else ...[
            if (isMinor) ...[
              const HintBox(text: "You're under 18, so a parent or legal guardian needs to sign on your behalf."),
              const SizedBox(height: 8),
              FieldLabeled(label: "Parent / guardian full name", child: AppField(controller: _guardianName, onChanged: (_) => setState(() {}))),
              const SizedBox(height: 10),
            ],
            _SignatureCard(
              label: isMinor ? "Guardian signature" : "Your signature",
              savedSignature: isMinor ? null : record.adoptedSignatureImage,
              image: _signature,
              onCaptured: (img, method) => setState(() {
                _signature = img;
                _signatureMethod = method;
                _signatureAt = img == null ? null : _now();
              }),
            ),
          ],

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _busy ? null : () => _submit(isMinor: isMinor),
            child: Text(_busy ? "Signing…" : "Sign document"),
          ),
          const SizedBox(height: 8),
          const Text(
            "When you sign, we record the date, time, your IP address and device, and email you a signed PDF.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(({String id, String title, String? emailedTo}) done) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar(onBack: widget.onDone ?? widget.onBack, title: "Signed"),
          const SizedBox(height: 10),
          AppCard(
            borderColor: AppColors.gold,
            child: Row(
              children: [
                const Icon(LucideIcons.checkCircle2, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "\"${done.title}\" is signed.${done.emailedTo != null ? " A copy was emailed to ${done.emailedTo}." : ""} "
                    "It's saved under Signatures, and ONE Fitness can see it too.",
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_pdfDataUrl != null)
            DownloadPdfButton(filename: "${done.title}.pdf", pdfDataUrl: _pdfDataUrl!, label: "Open signed PDF")
          else
            const Center(child: Padding(padding: EdgeInsets.all(8), child: Text("Preparing your PDF…", style: TextStyle(fontSize: 12, color: AppColors.mute)))),
          const SizedBox(height: 12),
          if (widget.onDone != null)
            BtnGold(full: true, onPressed: widget.onDone, child: Text(widget.doneLabel))
          else
            BtnGhost(full: true, onPressed: widget.onBack, child: Text(widget.doneLabel)),
        ],
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            child: Text("$n", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

/// One clause with its initial box. Box 1 adopts the initials (draw, or use
/// saved ones); boxes 2–5 show them and need their own confirm tap.
class _ClauseCard extends StatelessWidget {
  const _ClauseCard({
    required this.index,
    required this.clause,
    required this.initials,
    required this.savedInitials,
    required this.ackAt,
    required this.onAdopt,
    required this.onConfirm,
    required this.onClear,
  });

  final int index;
  final WaiverClause clause;
  final String? initials;
  final String? savedInitials;
  final String? ackAt;
  final void Function(String image, String method)? onAdopt;
  final VoidCallback? onConfirm;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final acked = ackAt != null;
    return AppCard(
      borderColor: acked ? AppColors.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${index + 1}. ${clause.title}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(clause.text, style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
          const SizedBox(height: 10),
          if (acked && initials != null)
            Row(
              children: [
                _ImageBox(dataUrl: initials!, height: 46, width: 110),
                const SizedBox(width: 10),
                const Icon(LucideIcons.checkCircle2, size: 15, color: AppColors.gold),
                const SizedBox(width: 4),
                const Expanded(child: Text("Initialled", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700))),
                if (onClear != null)
                  TextButton(onPressed: onClear, child: const Text("Clear and redraw", style: TextStyle(fontSize: 11))),
              ],
            )
          else if (index == 0) ...[
            // First box: adopt the initials for this document.
            if (savedInitials != null) ...[
              Row(
                children: [
                  _ImageBox(dataUrl: savedInitials!, height: 46, width: 110),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BtnGhost(
                      onPressed: () => onAdopt?.call(savedInitials!, "adopted"),
                      child: const Text("Use my saved initials", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text("or draw new initials:", style: TextStyle(fontSize: 11, color: AppColors.mute)),
              ),
            ],
            _PadWithConfirm(height: 170, confirmLabel: "Use these initials", onConfirm: (img) => onAdopt?.call(img, "draw")),
          ] else if (initials == null)
            const Text("Initial the first section to continue.", style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic))
          else
            Row(
              children: [
                Opacity(opacity: 0.45, child: _ImageBox(dataUrl: initials!, height: 46, width: 110)),
                const SizedBox(width: 10),
                Expanded(child: BtnGold(onPressed: onConfirm, child: const Text("Tap to initial", style: TextStyle(fontSize: 12)))),
              ],
            ),
        ],
      ),
    );
  }
}

/// The final signature: use the saved one (an explicit tap), or draw one,
/// with "Clear and redraw" until submit.
class _SignatureCard extends StatefulWidget {
  const _SignatureCard({required this.label, required this.savedSignature, required this.image, required this.onCaptured});
  final String label;
  final String? savedSignature;
  final String? image;
  final void Function(String? image, String method) onCaptured;

  @override
  State<_SignatureCard> createState() => _SignatureCardState();
}

class _SignatureCardState extends State<_SignatureCard> {
  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (image != null) ...[
            _ImageBox(dataUrl: image, height: 90, width: double.infinity),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.checkCircle2, size: 15, color: AppColors.gold),
                const SizedBox(width: 4),
                const Expanded(child: Text("Signed", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => widget.onCaptured(null, "draw"), child: const Text("Clear and redraw", style: TextStyle(fontSize: 11))),
              ],
            ),
          ] else ...[
            if (widget.savedSignature != null) ...[
              _ImageBox(dataUrl: widget.savedSignature!, height: 70, width: double.infinity),
              const SizedBox(height: 6),
              BtnGhost(
                full: true,
                onPressed: () => widget.onCaptured(widget.savedSignature, "adopted"),
                child: const Text("Use my saved signature"),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text("or draw a new signature:", style: TextStyle(fontSize: 11, color: AppColors.mute)),
              ),
            ],
            _PadWithConfirm(height: 230, confirmLabel: "Use this signature", onConfirm: (img) => widget.onCaptured(img, "draw")),
          ],
        ],
      ),
    );
  }
}

/// A signature pad plus an explicit "use this" button — drawing alone never
/// counts as signing; the confirm tap is the consent action.
class _PadWithConfirm extends StatefulWidget {
  const _PadWithConfirm({required this.height, required this.confirmLabel, required this.onConfirm});
  final double height;
  final String confirmLabel;
  final ValueChanged<String> onConfirm;

  @override
  State<_PadWithConfirm> createState() => _PadWithConfirmState();
}

class _PadWithConfirmState extends State<_PadWithConfirm> {
  String? _drawn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignaturePad(height: widget.height, onCaptured: (img) => setState(() => _drawn = img)),
        const SizedBox(height: 6),
        BtnGold(
          full: true,
          onPressed: _drawn == null ? null : () => widget.onConfirm(_drawn!),
          child: Text(widget.confirmLabel, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.dataUrl, required this.height, required this.width});
  final String dataUrl;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
      child: Image.memory(base64Decode(dataUrl.split(",").last), fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}

/// Plain-text waiver body with the editor's light `**bold**` / `*italic*` /
/// `- bullet` markup.
class _WaiverText extends StatelessWidget {
  const _WaiverText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split("\n").where((l) => l.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final bullet = line.trimLeft().startsWith("- ");
        final content = bullet ? line.trimLeft().substring(2) : line;
        return Padding(
          padding: EdgeInsets.only(bottom: 6, left: bullet ? 12 : 0),
          child: Text.rich(_richify(bullet ? "•  $content" : content), style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.txt)),
        );
      }).toList(),
    );
  }

  TextSpan _richify(String s) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r"\*\*(.+?)\*\*|\*(.+?)\*");
    var last = 0;
    for (final m in pattern.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      final b = m.group(1);
      spans.add(b != null
          ? TextSpan(text: b, style: const TextStyle(fontWeight: FontWeight.w800))
          : TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return TextSpan(children: spans);
  }
}

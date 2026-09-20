import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "../theme/app_colors.dart";

/// Same pattern as DownloadCsvButton — writes a `data:application/pdf;
/// base64,...` payload to a temp file and hands it to the OS share sheet
/// (Save to Files/email/etc.), the mobile equivalent of a browser PDF
/// download. Used for the signed-waiver completion certificate (Variable &
/// Signature Capture spec §6 — "made available to... the client
/// (download/email copy — required under ESIGN Act)").
class DownloadPdfButton extends StatefulWidget {
  const DownloadPdfButton({super.key, required this.filename, required this.pdfDataUrl, this.label = "Download PDF"});

  final String filename;
  final String pdfDataUrl;
  final String label;

  @override
  State<DownloadPdfButton> createState() => _DownloadPdfButtonState();
}

class _DownloadPdfButtonState extends State<DownloadPdfButton> {
  bool _busy = false;

  /// A name every filesystem accepts: no separators or reserved characters,
  /// no double spaces, and short enough not to hit a path-length limit —
  /// a document title like "Liability Waiver, Assumption of Risk, and
  /// Cancellation Policy Agreement" goes straight into this.
  static String safeFileName(String name) {
    var out = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), " ").replaceAll(RegExp(r"\s+"), " ").trim();
    if (out.toLowerCase().endsWith(".pdf")) out = out.substring(0, out.length - 4).trim();
    if (out.length > 60) out = out.substring(0, 60).trim();
    if (out.isEmpty) out = "document";
    return "$out.pdf";
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final b64 = widget.pdfDataUrl.split(",").last;
      final bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/${safeFileName(widget.filename)}");
      await file.writeAsBytes(bytes);
      final result = await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: "application/pdf")], subject: widget.filename),
      );
      // Nothing was picked (the sheet was dismissed) — say so rather than
      // leaving the tap looking like it did nothing at all.
      if (mounted && result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No app on this phone can open a PDF — the copy emailed to you opens in any browser.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open the PDF: ${e.toString().replaceFirst("Exception: ", "")}")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : _download,
      icon: Icon(LucideIcons.download, size: 14, color: _busy ? AppColors.mute : AppColors.gold),
      label: Text(
        _busy ? "Exporting…" : widget.label,
        style: TextStyle(color: _busy ? AppColors.mute : AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

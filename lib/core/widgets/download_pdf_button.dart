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

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final b64 = widget.pdfDataUrl.split(",").last;
      final bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/${widget.filename}");
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: "application/pdf")], subject: widget.filename));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't export — try again.")),
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

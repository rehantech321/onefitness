import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "../theme/app_colors.dart";
import "../utils/csv_utils.dart";

/// Mirrors every ReportTable.jsx instance's "Download CSV" button — writes
/// the CSV to a temp file and hands it to the OS share sheet (Save to
/// Files/Drive/email/etc.), the mobile equivalent of a browser file
/// download. [rows] includes the header row as its first entry.
class DownloadCsvButton extends StatefulWidget {
  const DownloadCsvButton({super.key, required this.filename, required this.rows});

  final String filename;
  final List<List<Object?>> rows;

  @override
  State<DownloadCsvButton> createState() => _DownloadCsvButtonState();
}

class _DownloadCsvButtonState extends State<DownloadCsvButton> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final csv = buildCsv(widget.rows);
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/${widget.filename}");
      await file.writeAsString(csv, encoding: utf8);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: "text/csv")], subject: widget.filename));
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
    // Only a header row (or nothing) to export — nothing worth downloading.
    final hasData = widget.rows.length > 1;
    return TextButton.icon(
      onPressed: !hasData || _busy ? null : _download,
      icon: Icon(LucideIcons.download, size: 14, color: hasData ? AppColors.gold : AppColors.mute),
      label: Text(
        _busy ? "Exporting…" : "Download CSV",
        style: TextStyle(color: hasData ? AppColors.gold : AppColors.mute, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

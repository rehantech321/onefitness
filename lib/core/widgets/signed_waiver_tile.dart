import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "app_card.dart";
import "download_pdf_button.dart";

/// One signed waiver with an "Open signed PDF" action. Shared by the
/// client's Signatures list and the Documents tab staff see on a client's
/// profile, so both show the same document the same way. The PDF is
/// fetched only when opened — it can be a few hundred KB.
class SignedWaiverTile extends StatefulWidget {
  const SignedWaiverTile({
    super.key,
    required this.signatureId,
    required this.title,
    required this.subtitle,
    this.detail,
  });

  final String signatureId;
  final String title;
  final String subtitle;

  /// Extra lines for staff — who signed, release choice, where it was emailed.
  final String? detail;

  @override
  State<SignedWaiverTile> createState() => _SignedWaiverTileState();
}

class _SignedWaiverTileState extends State<SignedWaiverTile> {
  String? _pdf;
  bool _loading = false;
  bool _missing = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pdf = await SupabaseService.loadWaiverSignaturePdf(widget.signatureId);
      if (!mounted) return;
      setState(() {
        _pdf = pdf;
        _missing = pdf == null;
      });
    } catch (_) {
      if (mounted) setState(() => _missing = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
                    Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                  ],
                ),
              ),
              const Icon(LucideIcons.check, size: 16, color: AppColors.grn),
            ],
          ),
          if (widget.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(widget.detail!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
            ),
          const SizedBox(height: 10),
          if (_pdf != null)
            DownloadPdfButton(filename: widget.title, pdfDataUrl: _pdf!, label: "Open signed PDF")
          else if (_missing)
            const Text("No PDF on file for this signature (signed before PDFs were stored).", style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic))
          else
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.goldDim)),
              icon: const Icon(LucideIcons.fileText, size: 14),
              label: Text(_loading ? "Loading…" : "View signed PDF", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

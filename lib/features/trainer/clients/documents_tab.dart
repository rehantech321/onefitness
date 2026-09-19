import "package:flutter/material.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/signed_waiver_tile.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_signature_record.dart";

/// Every waiver this client has signed, for the owner and coaches — each
/// with its signed PDF and the audit details that matter at a glance.
/// Reads straight from `waiver_signatures`, the tamper-proof record.
class DocumentsTab extends StatefulWidget {
  const DocumentsTab({super.key, required this.clientId});
  final String clientId;

  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  late Future<List<WaiverSignatureRecord>> _future = SupabaseService.loadWaiverSignatures(clientId: widget.clientId);

  @override
  void didUpdateWidget(covariant DocumentsTab old) {
    super.didUpdateWidget(old);
    if (old.clientId != widget.clientId) {
      _future = SupabaseService.loadWaiverSignatures(clientId: widget.clientId);
    }
  }

  String _when(DateTime d) {
    const m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return "${m[d.month - 1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, "0")} ${d.hour < 12 ? "AM" : "PM"}";
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async {
        final next = SupabaseService.loadWaiverSignatures(clientId: widget.clientId);
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<List<WaiverSignatureRecord>>(
        future: _future,
        builder: (context, snap) {
          final children = <Widget>[const SectionLabel("Signed Documents")];
          if (snap.connectionState != ConnectionState.done) {
            children.add(const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.gold))));
          } else if (snap.hasError) {
            children.add(const HintBox(text: "Couldn't load documents — pull down to try again."));
          } else if ((snap.data ?? const []).isEmpty) {
            children.add(const HintBox(text: "This client hasn't signed any documents yet."));
          } else {
            for (final s in snap.data!) {
              children.add(Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SignedWaiverTile(
                  signatureId: s.id,
                  title: s.docTitle,
                  subtitle: "Signed ${_when(s.signedAt)}",
                  detail: [
                    s.signerRole == "guardian" ? "Signed by guardian: ${s.guardianName ?? "—"}" : "Signed by the client",
                    "Photo/Video Release: ${s.photoVideoRelease ? "granted" : "declined — excluded from marketing"}",
                    if (s.emailedTo != null) "Copy emailed to ${s.emailedTo}",
                    if (s.signerIp != null) "IP ${s.signerIp}",
                  ].join("\n"),
                ),
              ));
            }
          }
          return ListView(padding: const EdgeInsets.all(18), children: children);
        },
      ),
    );
  }
}

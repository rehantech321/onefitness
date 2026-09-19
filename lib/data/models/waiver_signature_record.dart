/// One row of `waiver_signatures` — a completed, immutable signing event.
/// Listed without its PDF (which can be large); the PDF is fetched on
/// demand when someone opens it.
class WaiverSignatureRecord {
  const WaiverSignatureRecord({
    required this.id,
    required this.clientId,
    required this.docId,
    required this.docTitle,
    required this.signedAt,
    required this.signerRole,
    required this.documentVersionHash,
    this.guardianName,
    this.photoVideoRelease = false,
    this.emailedTo,
    this.signerIp,
  });

  final String id;
  final String clientId;
  final String docId;
  final String docTitle;
  final DateTime signedAt;
  final String signerRole; // client | guardian
  final String documentVersionHash;
  final String? guardianName;
  final bool photoVideoRelease;
  final String? emailedTo;
  final String? signerIp;

  factory WaiverSignatureRecord.fromRow(Map<String, dynamic> r) => WaiverSignatureRecord(
        id: r["id"] as String,
        clientId: r["client_id"] as String,
        docId: r["doc_id"] as String? ?? "",
        docTitle: r["doc_title"] as String? ?? "",
        signedAt: DateTime.tryParse(r["signed_at"] as String? ?? "")?.toLocal() ?? DateTime.now(),
        signerRole: r["signer_role"] as String? ?? "client",
        documentVersionHash: r["document_version_hash"] as String? ?? "",
        guardianName: r["guardian_name"] as String?,
        photoVideoRelease: r["photo_video_release"] as bool? ?? false,
        emailedTo: r["emailed_to"] as String?,
        signerIp: r["signer_ip"] as String?,
      );
}

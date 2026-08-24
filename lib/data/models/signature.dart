/// Mirrors one entry in client.signatures — a signed waiver/contract record.
class SignedDocument {
  const SignedDocument({required this.id, this.docId, required this.title, required this.signedAt, this.summary});

  final String id;

  /// The `waiver_docs` row this signature is for (ManageWaivers.jsx's
  /// `docSignedCount` matches on this, not [id]) — null for signatures
  /// written before this field existed.
  final String? docId;
  final String title;
  final String signedAt;
  final String? summary;
}

/// Mirrors one entry in client.signatures — a signed waiver/contract record.
class SignedDocument {
  const SignedDocument({required this.id, required this.title, required this.signedAt, this.summary});

  final String id;
  final String title;
  final String signedAt;
  final String? summary;
}

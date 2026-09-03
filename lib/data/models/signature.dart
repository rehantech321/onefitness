/// Mirrors one entry in client.signatures — a signed waiver/contract record.
/// Variable & Signature Capture spec: beyond the original id/title/date,
/// this now carries everything needed for a legally defensible e-signature
/// (California ESIGN Act/UETA) — the exact text signed, a server-verified
/// hash of the current document version at signing time, per-section
/// initials with their own timestamps, the final signature, the minor/
/// guardian block when applicable, the electronic-signing consent
/// acknowledgment, and the server-captured audit fields (IP, device, app
/// session). All of it is written exclusively by the sign-waiver edge
/// function (service-role) — never client-writable — so this data can't be
/// forged from the app itself.
class SignedDocument {
  const SignedDocument({
    required this.id,
    this.docId,
    required this.title,
    required this.signedAt,
    this.summary,
    this.signedBodyText,
    this.documentVersionHash,
    this.initialsImages = const [],
    this.initialsTimestamps = const [],
    this.signatureImage,
    this.guardianName,
    this.guardianSignatureImage,
    this.photoVideoOptOut,
    this.consentCheckboxAt,
    this.ipAddress,
    this.userAgent,
    this.sessionId,
    this.pdfDataUrl,
  });

  final String id;

  /// The `waiver_docs` row this signature is for (ManageWaivers.jsx's
  /// `docSignedCount` matches on this, not [id]) — null for signatures
  /// written before this field existed.
  final String? docId;
  final String title;
  final String signedAt;
  final String? summary;

  /// The exact, fully token-resolved body text the client actually signed —
  /// kept verbatim even if the owner edits or deletes the source
  /// `WaiverDoc` later, so this record always shows what was really agreed
  /// to.
  final String? signedBodyText;

  /// SHA-256 of the *current* `WaiverDoc.body` at the moment of signing,
  /// computed server-side. A booking-gate re-check compares this against a
  /// fresh hash of the live document — a mismatch means the policy changed
  /// since this signature and it no longer counts as current consent.
  final String? documentVersionHash;

  /// One entry per `{{initial}}` token in the document, in order — image
  /// data URLs rendered from the adopted initials (or freshly drawn/typed).
  final List<String> initialsImages;

  /// Parallel to [initialsImages] — each entry's own confirm-tap timestamp
  /// (ISO), not just one timestamp for the whole document.
  final List<String> initialsTimestamps;

  /// The final `{{signature}}` capture — data URL.
  final String? signatureImage;

  /// Present only when the client was a minor at signing time.
  final String? guardianName;
  final String? guardianSignatureImage;

  /// Snapshot of the client's photo/video release choice at the moment
  /// this specific document was signed (only meaningful for a document
  /// whose body includes a `{{photo_opt_out}}` token) — true means they
  /// declined.
  final bool? photoVideoOptOut;

  /// Separate "I agree to sign this document electronically" acknowledgment
  /// timestamp — required under the federal ESIGN Act / California UETA,
  /// distinct from the signature/initials themselves.
  final String? consentCheckboxAt;

  final String? ipAddress;

  /// Flutter has no browser user-agent — this is the practical equivalent:
  /// platform + OS version + app version, captured server-side from what
  /// the client sent.
  final String? userAgent;

  /// The authenticated Supabase session this signing event happened under.
  final String? sessionId;

  /// The generated completion-certificate PDF (signed text + audit summary)
  /// as a data URL — same storage convention this app already uses for
  /// progress photos and nutrition-plan PDF attachments.
  final String? pdfDataUrl;
}

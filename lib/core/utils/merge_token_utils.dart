import "dart:convert";
import "package:crypto/crypto.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/signature.dart";
import "../../data/models/trainer.dart";
import "../../data/models/waiver_doc.dart";
import "date_utils.dart";

/// Variable & Signature Capture spec, §1 — app-wide merge-token variables.
/// Not waiver-specific: any screen that needs to drop live client data into
/// text (waivers, contracts, in-app messages, notifications) resolves
/// `{{token}}` occurrences through the same map this builds, so every
/// surface agrees on what each token means.
///
/// Four tokens are deliberately NOT included here — `{{initial}}`,
/// `{{signature}}`, `{{guardian_signature}}`, `{{photo_opt_out}}` — those
/// are structural (they mark where an interactive capture widget goes, not
/// where text goes) and are handled by [parseWaiverSegments] instead, after
/// this map's substitution has already run.
Map<String, String> buildMergeTokenValues({
  required ClientInfo info,
  ClientRecord? record,
  Trainer? coach,
  String? businessName,
  MembershipPlan? plan,
}) {
  final parts = info.name.trim().split(RegExp(r"\s+"));
  final first = parts.isNotEmpty ? parts.first : info.name;
  final last = parts.length > 1 ? parts.sublist(1).join(" ") : "";
  final personalTraining = record?.intake["personalTraining"];
  final ecName = personalTraining?.answers["ecName"]?.toString();
  final ecPhone = personalTraining?.answers["ecPhone"]?.toString();

  return {
    "client_first_name": first,
    "client_last_name": last,
    "client_full_name": info.name,
    "client_dob": info.birthday ?? "",
    "emergency_contact_name": ecName ?? "",
    "emergency_contact_phone": ecPhone ?? "",
    "coach_name": coach?.name ?? "",
    "signature_date": isoToday(),
    "guardian_name": record?.guardianName ?? "",

    // ── The gym, and the plan this document is attached to ──────────────
    // A membership agreement has to state what the client is actually
    // being charged. Without these the price had to be typed into the
    // contract by hand, which goes stale the moment a plan's price changes
    // and leaves already-signed agreements disagreeing with what is
    // actually billed.
    "business_name": businessName ?? "",
    "plan_name": plan?.name ?? "",
    "sessions_per_month": plan?.maxSessions?.toString() ?? "",
    "billing_amount": plan == null ? "" : _money(plan.priceCents),
    // Price divided by the monthly allowance. Blank rather than a division
    // by zero for a plan with no session count (an unlimited membership or
    // a program), so the sentence reads oddly rather than showing "\$0.00"
    // as though sessions were free.
    "session_rate": (plan == null || (plan.maxSessions ?? 0) <= 0)
        ? ""
        : _money((plan.priceCents / plan.maxSessions!).round()),
    // "the 14th" — the day of the month their card is charged.
    "billing_anchor_date": info.billingAnchorDay == null ? "" : _ordinalDay(info.billingAnchorDay!),
    "membership_start_date": _planStart(info, plan?.id),
  };
}

String _money(int cents) => "\$${(cents / 100).toStringAsFixed(2)}";

/// "1st", "2nd", "3rd", "11th"… — the ordinals a billing date is spoken as.
String _ordinalDay(int day) {
  if (day >= 11 && day <= 13) return "${day}th";
  return switch (day % 10) {
    1 => "${day}st",
    2 => "${day}nd",
    3 => "${day}rd",
    _ => "${day}th",
  };
}

/// When this client started on this plan. Blank when it is not recorded —
/// a contract signed before the plan is bought has no start date yet, and
/// an invented one would be worse than a gap.
String _planStart(ClientInfo info, String? planId) {
  if (planId == null) return "";
  for (final pl in info.plans) {
    if (pl.planId == planId && pl.status == "active") return pl.startDate;
  }
  return "";
}

final _tokenPattern = RegExp(r"\{\{\s*([a-zA-Z_]+)\s*\}\}");

/// Replaces every `{{token}}` found in [values] — anything not in the map
/// (the four structural tokens above, or a typo) is left untouched so
/// [parseWaiverSegments] can still find the structural ones, and so a typo
/// fails loudly/visibly instead of silently vanishing.
String resolveMergeTokens(String text, Map<String, String> values) =>
    text.replaceAllMapped(_tokenPattern, (m) {
      final key = m.group(1)!;
      return values.containsKey(key) ? values[key]! : m.group(0)!;
    });

/// True once [record]/[info] have what's needed to resolve every
/// non-structural token a waiver could reasonably use — specifically the
/// emergency contact, which the spec calls out as "required before waiver
/// unlocks" (§1). Everything else (name/dob/etc.) always comes from data
/// that already exists on the account.
bool hasRequiredContactInfo(ClientRecord record) {
  final answers = record.intake["personalTraining"]?.answers;
  final name = answers?["ecName"]?.toString().trim();
  final phone = answers?["ecPhone"]?.toString().trim();
  return (name?.isNotEmpty ?? false) && (phone?.isNotEmpty ?? false);
}

/// Age in whole years as of today — used to gate the minor/guardian flow
/// (client_dob under 18). Null if no birthday is on file.
int? ageFromBirthday(String? birthday) {
  if (birthday == null || birthday.isEmpty) return null;
  final dob = DateTime.tryParse(birthday);
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
  return age;
}

/// One piece of a parsed waiver body — either plain (already merge-token-
/// resolved) text to render, or a marker for where an interactive capture
/// widget belongs. [WaiverInitialSegment.index] is 1-based and assigned in
/// document order, matching the spec's `initial_1_image…initial_N_image`
/// naming (generalized to however many `{{initial}}` tokens the document
/// actually has, not hardcoded to 5).
sealed class WaiverSegment {
  const WaiverSegment();
}

class WaiverTextSegment extends WaiverSegment {
  const WaiverTextSegment(this.text);
  final String text;
}

class WaiverInitialSegment extends WaiverSegment {
  const WaiverInitialSegment(this.index);
  final int index;
}

class WaiverSignatureSegment extends WaiverSegment {
  const WaiverSignatureSegment();
}

class WaiverGuardianSignatureSegment extends WaiverSegment {
  const WaiverGuardianSignatureSegment();
}

class WaiverPhotoOptOutSegment extends WaiverSegment {
  const WaiverPhotoOptOutSegment();
}

final _structuralPattern = RegExp(r"\{\{\s*(initial|signature|guardian_signature|photo_opt_out)\s*\}\}");

/// Splits an already merge-token-resolved waiver body into a flat, ordered
/// list the signing screen renders straight through — text segments as
/// formatted text, structural segments as their matching capture widget.
List<WaiverSegment> parseWaiverSegments(String resolvedBody) {
  final segments = <WaiverSegment>[];
  var initialCount = 0;
  var lastEnd = 0;
  for (final m in _structuralPattern.allMatches(resolvedBody)) {
    if (m.start > lastEnd) segments.add(WaiverTextSegment(resolvedBody.substring(lastEnd, m.start)));
    switch (m.group(1)) {
      case "initial":
        initialCount++;
        segments.add(WaiverInitialSegment(initialCount));
      case "signature":
        segments.add(const WaiverSignatureSegment());
      case "guardian_signature":
        segments.add(const WaiverGuardianSignatureSegment());
      case "photo_opt_out":
        segments.add(const WaiverPhotoOptOutSegment());
    }
    lastEnd = m.end;
  }
  if (lastEnd < resolvedBody.length) segments.add(WaiverTextSegment(resolvedBody.substring(lastEnd)));
  return segments;
}

/// Total `{{initial}}` tokens in a body — used up front to size the
/// initials-capture list before walking the document.
int countInitialSegments(String resolvedBody) => _structuralPattern.allMatches(resolvedBody).where((m) => m.group(1) == "initial").length;

/// SHA-256 of the RAW (not merge-token-resolved) document body — same
/// value sign-waiver computes and stores as `documentVersionHash`. Hashing
/// the raw body (not the per-client-resolved text) means the hash tracks
/// changes to the *policy*, not each client's own name/date substitution.
String documentVersionHash(String rawBody) => sha256.convert(utf8.encode(rawBody)).toString();

/// True when [sig] is a currently-valid signature for [doc] — same
/// document id AND the owner hasn't edited the body since this was signed.
/// A stale signature (hash mismatch) should be treated exactly like never
/// having signed at all — this is the client-side mirror of the
/// booking-gate check the spec calls for in §5.
bool isCurrentSignature(SignedDocument sig, WaiverDoc doc) => sig.docId == doc.id && sig.documentVersionHash == documentVersionHash(doc.body);

/// Every non-archived, currently-applicable [WaiverDoc] the client hasn't
/// (currently) signed yet — "general" scope always applies; "plan" scope
/// only applies if it matches a plan the client actually holds. Used both to
/// gate booking and to build the "needs your signature" list on the
/// Signatures screen.
///
/// [clientPlanIds] is every held plan (`ClientInfo.heldPlanIds`), not just
/// the membership slot: a package bought alongside a membership never takes
/// that slot, so checking it alone silently excused that package's contract
/// from both the prompt and the booking gate.
List<WaiverDoc> outstandingWaivers({
  required List<WaiverDoc> allDocs,
  required List<SignedDocument> signatures,
  required Set<String> clientPlanIds,
}) =>
    allDocs.where((d) {
      if (d.archived || !d.required) return false;
      if (d.scope == "plan" && !clientPlanIds.contains(d.planId)) return false;
      final signed = signatures.where((s) => s.docId == d.id);
      return signed.isEmpty || !isCurrentSignature(signed.first, d);
    }).toList();

/// One clause the client initials. Order and keys must match CLAUSES in
/// supabase/functions/sign-waiver — the server rejects a submission that
/// doesn't initial every one of them.
class WaiverClause {
  const WaiverClause(this.key, this.title, this.text);
  final String key;
  final String title;
  final String text;
}

const kWaiverClauses = [
  WaiverClause("assumption_of_risk", "Assumption of Risk",
      "I understand that physical training carries an inherent risk of injury, and I voluntarily accept those risks."),
  WaiverClause("release_of_liability", "Release of Liability",
      "I release ONE Fitness, its owners, coaches and staff from liability for injury or loss arising from my participation, except where caused by gross negligence."),
  WaiverClause("medical_disclosure", "Medical Disclosure",
      "I have disclosed any medical condition that may affect my training, and I will tell my coach promptly if my health changes."),
  WaiverClause("no_refund", "No Refund Policy",
      "I understand that memberships, packages and sessions are non-refundable once purchased."),
  WaiverClause("late_cancellation", "Late Cancellation / No-Show Policy",
      "I understand that late cancellations and no-shows may be charged a fee and that a no-show forfeits the session."),
];

/// The waiver text as the client reads it: merge tokens filled in, and the
/// old inline `{{initial}}`/`{{signature}}` markers removed — the clauses
/// and signature are now captured in their own section below the text.
String readableWaiverText(String body, Map<String, String> values) => resolveMergeTokens(
      body
          .replaceAll(RegExp(r"\{\{\s*(initial|signature|guardian_signature|photo_opt_out)\s*\}\}"), "")
          // Numbered markers ({{initial_1}}…) point at the clause boxes below.
          .replaceAllMapped(RegExp(r"\{\{\s*initial_(\d+)\s*\}\}"), (m) => "(initial box ${m.group(1)} below)"),
      values,
    ).trim();

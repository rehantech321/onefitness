import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/legal/privacy_policy_text.dart";
import "package:onefitness/core/legal/terms_text.dart";

/// The Privacy Policy and Terms carry specific language that carrier (A2P
/// 10DLC) and App Store reviewers look for. Losing a clause in a future
/// edit would fail a review with no other warning, so the load-bearing
/// sentences are pinned here.
/// The documents are hard-wrapped for readability, so a required sentence
/// often spans a line break. What matters is that the sentence is present,
/// not where it wraps — so compare with whitespace collapsed.
String flat(String s) => s.replaceAll(RegExp(r"\s+"), " ");

void main() {
  final policy = flat(kPrivacyPolicy);
  final terms = flat(kTermsOfUse);

  group("privacy policy — what carriers check", () {
    test("carries the mobile-information sharing clause verbatim", () {
      // Carriers look for this exact commitment; paraphrasing it fails.
      expect(
        policy,
        contains("No mobile information will be shared with third parties or affiliates "
            "for marketing or promotional purposes"),
      );
      expect(policy, contains("will not be shared with any third parties"));
    });

    test("states consent is not a condition of purchase", () {
      expect(policy, contains("not a condition of purchasing any service"));
    });

    test("gives STOP, HELP and a real contact route", () {
      expect(policy, contains("Reply STOP"));
      expect(policy, contains("Reply HELP"));
      expect(policy, contains("info@onefitnessworkout.com"));
      expect(policy, contains("(818) 223-7001"));
    });

    test("no unfilled placeholders are shown to users", () {
      for (final p in const ["[EMAIL]", "[PHONE]", "[LEGAL BUSINESS NAME]", "[8]"]) {
        expect(policy, isNot(contains(p)), reason: "$p was never filled in");
      }
    });
  });

  group("terms — SMS program", () {
    test("names the program and its frequency", () {
      expect(terms, contains("ONE Fitness Client Alerts"));
      expect(terms, contains("up to 8 messages per month"));
    });

    test("lists every opt-out keyword carriers expect", () {
      for (final k in const ["STOP", "CANCEL", "END", "QUIT", "UNSUBSCRIBE"]) {
        expect(terms, contains(k), reason: "$k must be honoured and documented");
      }
    });

    test("says consent is optional and unchecked", () {
      expect(terms, contains("optional, unchecked SMS consent box"));
      expect(terms, contains("Consent is not a condition of any purchase"));
    });
  });

  group("terms — Apple guideline 1.2", () {
    test("keeps the zero-tolerance clause", () {
      // Removing Part D in a future edit would fail App Review, and the
      // supplied business Terms do not contain this language.
      expect(terms, contains("zero tolerance for objectionable content or abusive users"));
    });

    test("documents reporting, blocking and the 24-hour commitment", () {
      expect(terms, contains("Report action"));
      expect(terms, contains("Blocked users"));
      expect(terms, contains("within 24 hours"));
    });

    test("documents account deletion", () {
      expect(terms, contains("Delete Account"));
      expect(terms, contains("Deletion is permanent"));
    });
  });

  test("the terms version is set, so a revision re-prompts acceptance", () {
    expect(kTermsVersion, isNotEmpty);
    expect(kTermsEffectiveDate, isNotEmpty);
  });
}

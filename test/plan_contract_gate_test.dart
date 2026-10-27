import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/booking_utils.dart";
import "package:onefitness/core/utils/merge_token_utils.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_plan.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/signature.dart";
import "package:onefitness/data/models/waiver_doc.dart";

/// When a plan's contract has to be signed.
///
/// Staff buying for a client are no longer blocked at the till; the client
/// signs in their own app and cannot book until they do. That only holds if
/// the booking gate actually sees the contract — and for a package bought
/// alongside a membership it did not, because the gate looked at the single
/// `membershipPlanId` slot that such a package never occupies.
void main() {
  const packageContract = WaiverDoc(
    id: "doc-pkg",
    title: "SEMI-PRIVATE TRAINING PACKAGE — 8 SESSIONS",
    body: "Package terms.",
    scope: "plan",
    planId: "plan-pkg-8",
  );
  const membershipContract = WaiverDoc(
    id: "doc-mem",
    title: "Membership agreement",
    body: "Membership terms.",
    scope: "plan",
    planId: "plan-mem",
  );
  const generalWaiver = WaiverDoc(
    id: "doc-gen",
    title: "Liability waiver",
    body: "General terms.",
    scope: "general",
  );

  ClientInfo client({String? membershipPlanId, List<ClientPlanEnrollment> plans = const []}) =>
      ClientInfo(id: "c1", name: "Ahmad", membershipPlanId: membershipPlanId, plans: plans);

  ClientPlanEnrollment held(String planId, {String status = "active"}) =>
      ClientPlanEnrollment(planId: planId, status: status, startDate: "2026-10-01");

  group("heldPlanIds", () {
    test("includes the membership slot", () {
      expect(client(membershipPlanId: "plan-mem").heldPlanIds, {"plan-mem"});
    });

    test("includes an active enrolment that never took the slot", () {
      // The case this whole fix turns on: a package bought on top of a
      // membership. enroll-free-plan's `takesSlot` leaves the slot alone, so
      // the package exists only here.
      final info = client(
        membershipPlanId: "plan-mem",
        plans: [held("plan-pkg-8")],
      );
      expect(info.heldPlanIds, {"plan-mem", "plan-pkg-8"});
    });

    test("ignores a cancelled enrolment", () {
      final info = client(plans: [held("plan-pkg-8", status: "cancelled")]);
      expect(info.heldPlanIds, isEmpty);
    });

    test("a client holding nothing holds nothing", () {
      expect(client().heldPlanIds, isEmpty);
    });
  });

  group("outstandingWaivers", () {
    test("a package contract is outstanding even with the slot taken", () {
      final info = client(membershipPlanId: "plan-mem", plans: [held("plan-pkg-8")]);
      final out = outstandingWaivers(
        allDocs: const [packageContract],
        signatures: const [],
        clientPlanIds: info.heldPlanIds,
      );
      expect(out.map((d) => d.id), ["doc-pkg"]);
    });

    test("a contract for a plan they don't hold is not demanded of them", () {
      final info = client(membershipPlanId: "plan-mem");
      final out = outstandingWaivers(
        allDocs: const [packageContract],
        signatures: const [],
        clientPlanIds: info.heldPlanIds,
      );
      expect(out, isEmpty);
    });

    test("signing it clears it", () {
      final info = client(plans: [held("plan-pkg-8")]);
      final sig = SignedDocument(
        id: "sig-1",
        docId: "doc-pkg",
        title: packageContract.title,
        signedAt: "2026-10-26",
        documentVersionHash: documentVersionHash(packageContract.body),
      );
      final out = outstandingWaivers(
        allDocs: const [packageContract],
        signatures: [sig],
        clientPlanIds: info.heldPlanIds,
      );
      expect(out, isEmpty);
    });

    test("an edited contract has to be signed again", () {
      final info = client(plans: [held("plan-pkg-8")]);
      const stale = SignedDocument(
        id: "sig-old",
        docId: "doc-pkg",
        title: "SEMI-PRIVATE TRAINING PACKAGE — 8 SESSIONS",
        signedAt: "2026-09-01",
        documentVersionHash: "hash-of-the-old-wording",
      );
      final out = outstandingWaivers(
        allDocs: const [packageContract],
        signatures: const [stale],
        clientPlanIds: info.heldPlanIds,
      );
      expect(out.map((d) => d.id), ["doc-pkg"]);
    });

    test("general waivers still apply to everyone", () {
      final out = outstandingWaivers(
        allDocs: const [generalWaiver],
        signatures: const [],
        clientPlanIds: client().heldPlanIds,
      );
      expect(out.map((d) => d.id), ["doc-gen"]);
    });

    test("only the contracts for plans actually held come back", () {
      final info = client(membershipPlanId: "plan-mem", plans: [held("plan-pkg-8")]);
      final out = outstandingWaivers(
        allDocs: const [packageContract, membershipContract, generalWaiver],
        signatures: const [],
        clientPlanIds: info.heldPlanIds,
      );
      expect(out.map((d) => d.id).toSet(), {"doc-pkg", "doc-mem", "doc-gen"});
    });
  });

  group("the booking gate", () {
    test("blocks a client whose package contract is unsigned", () {
      // The admin was not stopped at the till; this is what makes the
      // contract real instead of optional.
      final info = client(membershipPlanId: "plan-mem", plans: [held("plan-pkg-8")]);
      final check = waiverGateCheck(
        info: info,
        record: const ClientRecord(id: "c1"),
        waiverDocs: const [packageContract],
      );
      expect(check, isNotNull);
      expect(check!.reason, "waiver-required");
      expect(check.msg, contains("SEMI-PRIVATE TRAINING PACKAGE"));
    });

    test("lets them book once it's signed", () {
      final info = client(plans: [held("plan-pkg-8")]);
      final record = ClientRecord(
        id: "c1",
        signatures: [
          SignedDocument(
            id: "sig-1",
            docId: "doc-pkg",
            title: packageContract.title,
            signedAt: "2026-10-26",
            documentVersionHash: documentVersionHash(packageContract.body),
          ),
        ],
      );
      expect(
        waiverGateCheck(info: info, record: record, waiverDocs: const [packageContract]),
        isNull,
      );
    });

    test("staff booking themselves are not gated", () {
      const staff = ClientInfo(id: "coach-1", name: "Coach", isStaff: true, membershipPlanId: "plan-mem");
      expect(
        waiverGateCheck(
          info: staff,
          record: const ClientRecord(id: "coach-1"),
          waiverDocs: const [membershipContract],
        ),
        isNull,
      );
    });

    test("names several outstanding documents by count, not by listing them", () {
      final info = client(membershipPlanId: "plan-mem", plans: [held("plan-pkg-8")]);
      final check = waiverGateCheck(
        info: info,
        record: const ClientRecord(id: "c1"),
        waiverDocs: const [packageContract, membershipContract],
      );
      expect(check!.msg, contains("2 documents"));
    });
  });
}

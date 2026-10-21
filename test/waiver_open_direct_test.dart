import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/waiver_doc.dart";

/// Tapping "Sign now" used to land the client on the Signatures list, so
/// they had to find the document they had just agreed to sign. It now opens
/// that document directly.
///
/// The decision of what to open is what these cover. It has to cope with
/// the waiver list not having loaded yet — the prompt can appear on a cold
/// start — without either hanging on a document that is never coming, or
/// giving up before the list arrives.
void main() {
  WaiverDoc doc(String id, {String title = "Waiver", bool archived = false}) =>
      WaiverDoc(id: id, title: title, body: "…", archived: archived);

  /// Mirrors the screen's rule: open the requested document once the list
  /// holds it; stop waiting once the list has arrived without it.
  ({WaiverDoc? open, bool settled}) decide({
    required String? wanted,
    required List<WaiverDoc> allDocs,
  }) {
    if (wanted == null) return (open: null, settled: true);
    final match = allDocs.where((d) => d.id == wanted);
    if (match.isNotEmpty) return (open: match.first, settled: true);
    // Empty list means "not loaded yet", so keep waiting.
    if (allDocs.isEmpty) return (open: null, settled: false);
    // Loaded, and it isn't there — archived or deleted since the prompt.
    return (open: null, settled: true);
  }

  group("opening the requested waiver", () {
    final docs = [doc("w1", title: "Liability Waiver"), doc("w2", title: "Photo Release")];

    test("opens the one that was asked for", () {
      final result = decide(wanted: "w1", allDocs: docs);
      expect(result.open?.id, "w1");
      expect(result.settled, isTrue);
    });

    test("opens the right one when there are several", () {
      expect(decide(wanted: "w2", allDocs: docs).open?.title, "Photo Release");
    });

    test("nothing requested means the list, as before", () {
      final result = decide(wanted: null, allDocs: docs);
      expect(result.open, isNull);
      expect(result.settled, isTrue);
    });
  });

  group("when the waiver list hasn't loaded yet", () {
    test("it keeps waiting rather than falling back to the list", () {
      // The prompt can appear on a cold start, before the documents have
      // arrived. Giving up here is what would drop the client on the list.
      final result = decide(wanted: "w1", allDocs: const []);
      expect(result.open, isNull);
      expect(result.settled, isFalse);
    });

    test("and opens it the moment the list arrives", () {
      expect(decide(wanted: "w1", allDocs: const []).settled, isFalse);
      expect(decide(wanted: "w1", allDocs: [doc("w1")]).open?.id, "w1");
    });
  });

  group("when the requested waiver isn't there", () {
    test("it settles on the list instead of hanging", () {
      // Archived or deleted between the prompt and arriving here. Waiting
      // for a document that is never coming would leave a blank screen.
      final result = decide(wanted: "gone", allDocs: [doc("w1")]);
      expect(result.open, isNull);
      expect(result.settled, isTrue);
    });
  });

  group("the request is for one trip only", () {
    /// The shell clears it once the screen reports it has acted.
    String? afterOpening(String? pending) => null;

    test("it is forgotten once acted on", () {
      // Otherwise the waiver springs open on every later visit — including
      // after it has been signed, which would make the client's own list of
      // signatures unreachable.
      expect(afterOpening("w1"), isNull);
    });

    /// And cleared on navigating anywhere that isn't Signatures.
    String? afterGoing(String? pending, String key) => key == "signatures" ? pending : null;

    test("it survives the trip to Signatures", () {
      expect(afterGoing("w1", "signatures"), "w1");
    });

    test("but not a trip anywhere else", () {
      expect(afterGoing("w1", "dashboard"), isNull);
      expect(afterGoing("w1", "booking"), isNull);
    });
  });
}

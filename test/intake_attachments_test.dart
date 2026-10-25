import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/supabase/supabase_service.dart";
import "package:onefitness/data/intake_forms.dart";
import "package:onefitness/data/models/intake_schema.dart";

/// Files attached to an intake form.
///
/// The bytes live in a private storage bucket and the record keeps only a
/// pointer, so what these tests guard is the pointer: that it survives a
/// round trip, that a broken one is dropped rather than shown as a file that
/// can never open, and that the cap and the per-form opt-in say what the
/// bucket's own rules say.
void main() {
  const attachment = IntakeAttachment(
    id: "a1",
    name: "blood-panel.pdf",
    path: "client-1/nutritional/a1.pdf",
    size: 240000,
    contentType: "application/pdf",
    uploadedAt: "2026-10-25T09:00:00.000",
  );

  group("IntakeAttachment", () {
    test("survives a round trip through json", () {
      final back = IntakeAttachment.fromJson(attachment.toJson());
      expect(back, isNotNull);
      expect(back!.id, "a1");
      expect(back.name, "blood-panel.pdf");
      expect(back.path, "client-1/nutritional/a1.pdf");
      expect(back.size, 240000);
      expect(back.contentType, "application/pdf");
      expect(back.uploadedAt, "2026-10-25T09:00:00.000");
    });

    test("knows a PDF from a JPEG", () {
      expect(attachment.isPdf, isTrue);
      expect(
        const IntakeAttachment(
          id: "a2",
          name: "scan.jpg",
          path: "client-1/nutritional/a2.jpg",
          size: 10,
          contentType: "image/jpeg",
        ).isPdf,
        isFalse,
      );
    });

    test("a pointer with no path is dropped, not shown", () {
      // A row like this can only have come from a half-written record. Keeping
      // it would put a file in the list that no signed URL could ever resolve.
      expect(IntakeAttachment.fromJson(const {"id": "a1", "name": "x.pdf"}), isNull);
      expect(IntakeAttachment.fromJson(const {"id": "a1", "path": "", "name": "x.pdf"}), isNull);
      expect(IntakeAttachment.fromJson(const {"path": "p/q/r.pdf"}), isNull);
    });

    test("a pointer missing only its cosmetic fields still opens", () {
      final back = IntakeAttachment.fromJson(const {"id": "a1", "path": "c/n/a1.pdf"});
      expect(back, isNotNull);
      expect(back!.path, "c/n/a1.pdf");
      expect(back.name, "Attachment");
      expect(back.size, 0);
    });
  });

  group("IntakeRecord", () {
    test("defaults to no attachments", () {
      expect(const IntakeRecord().attachments, isEmpty);
    });

    test("copyWith swaps attachments and leaves the rest alone", () {
      const original = IntakeRecord(
        answers: {"goal": "Lose fat"},
        completed: true,
        at: "2026-10-01",
        by: "Client",
      );
      final updated = original.copyWith(attachments: const [attachment]);
      expect(updated.attachments.single.id, "a1");
      // Adding a file must not re-file the form under someone else — the
      // provenance the answers view shows comes from exactly these fields.
      expect(updated.by, "Client");
      expect(updated.at, "2026-10-01");
      expect(updated.completed, isTrue);
      expect(updated.answers, original.answers);
    });
  });

  group("which forms take files", () {
    test("the nutrition intake does", () {
      expect(assessmentDefFor("nutritional")?.allowsAttachments, isTrue);
    });

    test("the training intake and physical assessment don't", () {
      expect(assessmentDefFor("personalTraining")?.allowsAttachments, isFalse);
      expect(assessmentDefFor("physical")?.allowsAttachments, isFalse);
    });

    test("an unknown key resolves to nothing rather than throwing", () {
      expect(assessmentDefFor("not-a-form"), isNull);
    });

    test("every catalogued assessment is reachable by its own key", () {
      for (final group in kIntakeForms) {
        for (final a in group.assessments) {
          expect(assessmentDefFor(a.key)?.key, a.key);
        }
      }
    });
  });

  group("limits match the bucket's own", () {
    test("six files per form", () {
      expect(kMaxIntakeAttachments, 6);
    });

    test("the app's size ceiling is the one migration 31 set on the bucket", () {
      // The bucket is the rule and this is the same number said earlier, so a
      // client hears "too big" before waiting out a doomed upload. If one
      // moves without the other, uploads start failing with no explanation.
      expect(SupabaseService.kIntakeFileMaxBytes, 10 * 1024 * 1024);
    });

    test("the bucket name is the one the storage policies match on", () {
      expect(SupabaseService.kIntakeFilesBucket, "intake-files");
    });
  });
}

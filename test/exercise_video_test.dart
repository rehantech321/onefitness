import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http_parser/http_parser.dart";

import "package:onefitness/core/supabase/streamed_upload.dart";
import "package:onefitness/core/supabase/supabase_service.dart";
import "package:onefitness/data/models/exercise_def.dart";

/// Exercise demo videos.
///
/// Two things here are worth guarding. The multipart body is hand-written —
/// `storage_client` has no progress callback, so the upload speaks to the
/// storage endpoint directly — and a body the server won't parse means every
/// upload fails, with a message about a missing file rather than a malformed
/// one. And the progress fraction is what a coach reads to decide whether it
/// is safe to leave the screen, so it must not reach the end before the
/// upload has.
void main() {
  group("ExerciseDef video", () {
    const filmed = ExerciseDef(
      id: "back-squat",
      name: "Back Squat",
      movementPattern: "Squat",
      primaryMuscle: "Quads",
      videoPath: "back-squat/abc.mp4",
      videoName: "squat-demo.mp4",
    );

    test("hasVideo is true once there's a path", () {
      expect(filmed.hasVideo, isTrue);
    });

    test("an exercise nobody has filmed has no video", () {
      const bare = ExerciseDef(
        id: "x",
        name: "X",
        movementPattern: "Push",
        primaryMuscle: "Chest",
      );
      expect(bare.hasVideo, isFalse);
      expect(bare.videoPath, isNull);
    });

    test("an empty path counts as no video, not as a broken one", () {
      // A record written by something that stored "" instead of omitting the
      // key. Showing "Watch demo" for it would open a player on nothing.
      const blank = ExerciseDef(
        id: "x",
        name: "X",
        movementPattern: "Push",
        primaryMuscle: "Chest",
        videoPath: "",
      );
      expect(blank.hasVideo, isFalse);
    });

    test("the name is cosmetic — a clip with no name still plays", () {
      const unnamed = ExerciseDef(
        id: "x",
        name: "X",
        movementPattern: "Push",
        primaryMuscle: "Chest",
        videoPath: "x/abc.mp4",
      );
      expect(unnamed.hasVideo, isTrue);
      expect(unnamed.videoName, isNull);
    });
  });

  group("limits match the bucket's own", () {
    test("the size ceiling is the one migration 36 set", () {
      // The bucket is the rule and this is the same number said earlier, so a
      // coach hears "too big" before sitting through a doomed upload. If one
      // moves without the other, uploads start failing with no explanation.
      expect(SupabaseService.kExerciseVideoMaxBytes, 150 * 1024 * 1024);
    });

    test("the bucket name is the one the storage policies match on", () {
      expect(SupabaseService.kExerciseVideosBucket, "exercise-videos");
    });

    test("every offered extension maps to a type the bucket accepts", () {
      // migration 36's allowed_mime_types, verbatim.
      const accepted = {"video/mp4", "video/quicktime", "video/webm"};
      expect(SupabaseService.kExerciseVideoTypes, isNotEmpty);
      for (final entry in SupabaseService.kExerciseVideoTypes.entries) {
        expect(accepted, contains(entry.value), reason: entry.key);
      }
    });

    test("the extensions a coach can pick are the common phone formats", () {
      expect(
        SupabaseService.kExerciseVideoTypes.keys,
        containsAll(<String>["mp4", "mov"]),
      );
    });
  });

  group("multipart framing", () {
    final framing = multipartFraming(boundary: "BOUND", contentType: "video/mp4");
    final prologue = utf8.decode(framing.prologue);
    final epilogue = utf8.decode(framing.epilogue);

    test("opens each part with the boundary and closes with the terminator", () {
      expect(prologue, startsWith("--BOUND\r\n"));
      expect(epilogue, "\r\n--BOUND--\r\n");
    });

    test("carries the cacheControl field storage expects", () {
      expect(prologue, contains('name="cacheControl"'));
      expect(prologue, contains("\r\n\r\n3600\r\n"));
    });

    test("names the file part the way the storage client does", () {
      // An empty name and an empty filename. Both look wrong and are what
      // the server accepts; a null filename makes it reject the request.
      expect(prologue, contains('name=""; filename=""'));
    });

    test("declares the content type on the part, not just the request", () {
      // This header is where the stored object's type comes from, so a clip
      // uploaded without it comes back as a download instead of playing.
      expect(prologue, contains("content-type: video/mp4\r\n"));
      expect(
        utf8.decode(
          multipartFraming(boundary: "B", contentType: "video/quicktime").prologue,
        ),
        contains("content-type: video/quicktime\r\n"),
      );
    });

    test("ends the headers with a blank line, so the body starts clean", () {
      expect(prologue, endsWith("\r\n\r\n"));
    });

    test("is byte-for-byte what storage_client's own upload sends", () async {
      // The decisive one. Every test above checks our body against our own
      // reading of what the storage API wants; this checks it against what
      // the library actually puts on the wire for `uploadBinary` — the same
      // http.MultipartRequest, the same part name, filename, field and
      // ordering. If the two agree on the bytes, a body the server accepts
      // from the library is a body it accepts from us.
      //
      // Rebuilt from fetch.dart's _handleMultipartRequest: one file part
      // named '' with an empty filename, plus a cacheControl field.
      final file = List<int>.generate(3000, (i) => i % 256);
      final reference = http.MultipartRequest("POST", Uri.parse("https://x/y"))
        ..files.add(
          http.MultipartFile.fromBytes(
            "",
            file,
            filename: "",
            contentType: MediaType.parse("video/mp4"),
          ),
        )
        ..fields["cacheControl"] = "3600";

      // MultipartRequest invents its own boundary and sets the content-type
      // header only inside finalize(), so the stream has to be taken first
      // and the boundary read back off the header afterwards.
      final stream = reference.finalize();
      final boundary = MediaType.parse(
        reference.headers["content-type"]!,
      ).parameters["boundary"];
      expect(boundary, isNotNull, reason: "no boundary in ${reference.headers}");

      final expected = await stream.toBytes();

      final framing = multipartFraming(boundary: boundary!, contentType: "video/mp4");
      final ours = <int>[];
      await multipartBodyStream(
        framing: framing,
        body: Stream.value(file),
        total: framing.prologue.length + file.length + framing.epilogue.length,
      ).forEach(ours.addAll);

      expect(utf8.decode(ours, allowMalformed: true),
          utf8.decode(expected, allowMalformed: true));
      expect(ours, expected);
      expect(ours.length, reference.contentLength);
    });
  });

  group("upload progress", () {
    /// The file in [chunks], framed, with every reported fraction collected.
    Future<List<double>> run(List<List<int>> chunks) async {
      final framing = multipartFraming(boundary: "B", contentType: "video/mp4");
      final length = chunks.fold<int>(0, (sum, c) => sum + c.length);
      final total = framing.prologue.length + length + framing.epilogue.length;
      final seen = <double>[];
      await multipartBodyStream(
        framing: framing,
        body: Stream.fromIterable(chunks),
        total: total,
        onProgress: seen.add,
      ).drain<void>();
      return seen;
    }

    test("never reports a finished upload while bytes are still in flight", () {
      // The whole point of the cap. A full bar is the reading a coach would
      // act on by leaving the screen, and the request is not done until the
      // server has answered — which happens after this stream is drained.
      return run([List.filled(400 * 1024, 0), List.filled(400 * 1024, 0)])
          .then((seen) {
        expect(seen, isNotEmpty);
        expect(seen.last, lessThanOrEqualTo(0.99));
        expect(seen.every((f) => f <= 0.99), isTrue);
      });
    });

    test("only ever moves forward", () async {
      final seen = await run([
        for (var i = 0; i < 12; i++) List.filled(64 * 1024, 0),
      ]);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]));
      }
    });

    test("reaches most of the way through a large file", () async {
      final seen = await run([for (var i = 0; i < 40; i++) List.filled(256 * 1024, 0)]);
      expect(seen.last, greaterThan(0.9));
    });

    test("doesn't report a step per chunk", () async {
      // 200 chunks of 4KB is 800KB; reporting each one would rebuild the
      // progress bar 200 times for under a megabyte.
      final seen = await run([for (var i = 0; i < 200; i++) List.filled(4 * 1024, 0)]);
      expect(seen.length, lessThan(200));
    });

    test("the body streamed is the framing wrapped around the file", () async {
      final framing = multipartFraming(boundary: "B", contentType: "video/mp4");
      final file = [1, 2, 3, 4, 5];
      final total = framing.prologue.length + file.length + framing.epilogue.length;
      final out = <int>[];
      await multipartBodyStream(
        framing: framing,
        body: Stream.value(file),
        total: total,
      ).forEach(out.addAll);
      expect(out.length, total);
      expect(out, [...framing.prologue, ...file, ...framing.epilogue]);
    });

    test("an empty file still produces a parseable body", () async {
      // Nothing should pick one, but a zero-byte pick must not produce a
      // body that hangs the parser.
      final framing = multipartFraming(boundary: "B", contentType: "video/mp4");
      final total = framing.prologue.length + framing.epilogue.length;
      final out = <int>[];
      await multipartBodyStream(
        framing: framing,
        body: const Stream<List<int>>.empty(),
        total: total,
      ).forEach(out.addAll);
      expect(out, [...framing.prologue, ...framing.epilogue]);
    });
  });
}

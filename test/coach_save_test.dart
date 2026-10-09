import "dart:convert";
import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:image/image.dart" as img;
import "package:onefitness/core/utils/image_shrink.dart";
import "package:onefitness/core/utils/save_error.dart";
import "package:onefitness/data/models/trainer.dart";

void main() {
  test("an oversized before/after photo is shrunk before saving", () async {
    // A 1600x2400 noisy photo at high quality — the size older picks were.
    final rnd = Random(1);
    final photo = img.Image(width: 1600, height: 2400);
    for (final p in photo) {
      p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
    final big = "data:image/jpeg;base64,${base64Encode(img.encodeJpg(photo, quality: 95))}";
    expect(big.length, greaterThan(260000));

    final small = await shrinkDataUrlImage(big);
    expect(small.length, lessThan(big.length));
    final decoded = img.decodeImage(base64Decode(small.substring(small.indexOf(",") + 1)))!;
    expect(max(decoded.width, decoded.height), lessThanOrEqualTo(900));
  });

  test("small photos and URLs are left alone", () async {
    const url = "https://example.com/a.jpg";
    expect(await shrinkDataUrlImage(url), url);
    const tiny = "data:image/jpeg;base64,AAAA";
    expect(await shrinkDataUrlImage(tiny), tiny);
  });

  test("unchanged before/afters are recognised", () {
    const a = [TrainerBeforeAfter(id: "1", left: "x", right: "y")];
    expect(sameBeforeAfters(a, const [TrainerBeforeAfter(id: "1", left: "x", right: "y")]), isTrue);
    expect(sameBeforeAfters(a, const [TrainerBeforeAfter(id: "1", left: "x", right: "z")]), isFalse);
    expect(sameBeforeAfters(a, const []), isFalse);
  });

  test("save errors say what actually went wrong", () {
    expect(saveErrorMessage(Exception("objectionable_content: bio")), contains("bio"));
    expect(saveErrorMessage(Exception("SocketException: Failed host lookup")), contains("connection"));
    expect(saveErrorMessage(Exception("That phone number is already on another account.")),
        "Couldn't save: That phone number is already on another account.");
  });
}

import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Every avatar in the app must be given the person's photo.
///
/// This kept regressing one screen at a time: the widget has always
/// supported a photo and the photo has always been loaded, but each new
/// list was written as `Avatar(name: ...)` and quietly showed initials.
/// Fixing them one report at a time doesn't hold, so this walks the source
/// and fails if any avatar is built without one.
void main() {
  test("no Avatar is built without a photo", () {
    final offenders = <String>[];
    var total = 0;

    for (final entity in Directory("lib").listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith(".dart")) continue;
      // The widget's own definition is where `src` is declared.
      if (entity.path.replaceAll(r"\", "/").endsWith("core/widgets/avatar.dart")) continue;

      final source = entity.readAsStringSync();
      for (final match in RegExp(r"\bAvatar\s*\(").allMatches(source)) {
        // Walk to the matching close paren so a multi-line constructor is
        // read whole — checking only the first line is what let several of
        // these hide.
        var i = match.end - 1;
        var depth = 0;
        while (i < source.length) {
          if (source[i] == "(") depth++;
          if (source[i] == ")") {
            depth--;
            if (depth == 0) break;
          }
          i++;
        }
        final body = source.substring(match.end, i);
        total++;

        final line = "\n".allMatches(source.substring(0, match.start)).length + 1;
        if (!body.contains("src:")) {
          offenders.add("${entity.path}:$line — no src");
        } else if (RegExp(r"src:\s*null\b").hasMatch(body)) {
          // An explicit null is the same outcome as omitting it; if a photo
          // genuinely can't be reached, resolve it or say why here.
          offenders.add("${entity.path}:$line — src: null");
        }
      }
    }

    expect(total, greaterThan(20), reason: "the scan found suspiciously few avatars");
    expect(
      offenders,
      isEmpty,
      reason: "these avatars will show initials even when the person has a photo:\n"
          "${offenders.join("\n")}",
    );
  });
}

import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Chip rows need a gap vertically as well as horizontally.
///
/// A `Wrap` with only `spacing` looks right until its chips need a second
/// line — then the rows sit flush against each other and read as one solid
/// block. That's what happened to the Kind and Allowed session types rows
/// on the plan editor: the gap was there between chips and absent between
/// lines, which is the half nobody notices while the list is short.
void main() {
  test("every Wrap sets runSpacing, not just spacing", () {
    final offenders = <String>[];
    var total = 0;

    for (final entity in Directory("lib").listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith(".dart")) continue;
      final source = entity.readAsStringSync();

      for (final match in RegExp(r"\bWrap\s*\(").allMatches(source)) {
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

        // Only this Wrap's own arguments — anything after `children:`
        // belongs to the widgets inside it.
        final childrenAt = source.indexOf("children:", match.end);
        final args = source.substring(
          match.end,
          (childrenAt > 0 && childrenAt < i) ? childrenAt : i,
        );
        total++;

        if (!args.contains("runSpacing:")) {
          final line = "\n".allMatches(source.substring(0, match.start)).length + 1;
          offenders.add("${entity.path}:$line");
        }
      }
    }

    expect(total, greaterThan(40), reason: "the scan found suspiciously few Wrap widgets");
    expect(
      offenders,
      isEmpty,
      reason: "these chip rows will run together when they wrap to a second line:\n"
          "${offenders.join("\n")}",
    );
  });
}

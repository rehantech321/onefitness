import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/widgets/avatar.dart";

/// Coaches showed as initials in every staff list even when they had
/// uploaded a profile photo. The widget had always supported one and the
/// photo had always been loaded — the lists simply never passed it through.
void main() {
  /// A 1×1 PNG as the base64 data URL a profile photo is actually stored as
  /// (there's no object storage; photos round-trip inside profiles.photo_url).
  final pngBytes = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  );
  final dataUrl = "data:image/png;base64,${base64Encode(pngBytes)}";

  Future<Avatar> pump(WidgetTester tester, Avatar avatar) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: avatar)));
    return tester.widget<Avatar>(find.byType(Avatar));
  }

  /// The image the avatar ended up drawing, if any.
  DecorationImage? imageOf(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    for (final c in containers) {
      final d = c.decoration;
      if (d is BoxDecoration && d.image != null) return d.image;
    }
    return null;
  }

  group("showing a coach's photo", () {
    testWidgets("a stored photo is drawn, not their initials", (tester) async {
      await pump(tester, Avatar(src: dataUrl, name: "Chris McCarthy", size: 40));
      expect(imageOf(tester), isNotNull);
      expect(find.text("CM"), findsNothing);
    });

    testWidgets("the photo is decoded from the data URL it's stored as", (tester) async {
      await pump(tester, Avatar(src: dataUrl, name: "Chris McCarthy", size: 40));
      // MemoryImage, because a data URL is decoded rather than fetched.
      expect(imageOf(tester)!.image, isA<MemoryImage>());
    });

    testWidgets("a photo fills the circle rather than being letterboxed", (tester) async {
      await pump(tester, Avatar(src: dataUrl, name: "Chris McCarthy", size: 40));
      expect(imageOf(tester)!.fit, BoxFit.cover);
    });
  });

  group("falling back to initials", () {
    testWidgets("no photo gives initials", (tester) async {
      await pump(tester, const Avatar(name: "Chris McCarthy", size: 40));
      expect(find.text("CM"), findsOneWidget);
      expect(imageOf(tester), isNull);
    });

    testWidgets("an empty photo string gives initials, not a broken image", (tester) async {
      // A cleared photo saves as "" rather than null in some paths.
      await pump(tester, const Avatar(src: "", name: "Chris McCarthy", size: 40));
      expect(find.text("CM"), findsOneWidget);
      expect(imageOf(tester), isNull);
    });

    testWidgets("a single-word name gives one initial", (tester) async {
      await pump(tester, const Avatar(name: "Cher", size: 40));
      expect(find.text("C"), findsOneWidget);
    });

    testWidgets("a blank name doesn't crash the list", (tester) async {
      await pump(tester, const Avatar(name: "", size: 40));
      expect(find.text("?"), findsOneWidget);
    });

    testWidgets("only the first two words are used", (tester) async {
      await pump(tester, const Avatar(name: "Jean Claude Van Damme", size: 40));
      expect(find.text("JC"), findsOneWidget);
    });
  });
}

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/share_origin.dart";

/// Opening the signed waiver PDF failed on iPhone with:
///
///   sharePositionOrigin: argument must be set, {{0, 0}, {0, 0}} must be
///   non-zero and within coordinate space of source view
///
/// iOS shows the share sheet as a popover and insists on knowing which
/// rectangle it points at. The rect we hand it has to be non-empty and on
/// screen — those two conditions are exactly what these cover, because
/// getting either wrong brings back the same crash.
void main() {
  /// Lays out a button of the given size and returns the rect computed
  /// from its context, as the export buttons do when tapped.
  ///
  /// Read through a key rather than by tapping: a zero-sized button can't
  /// be tapped, and that is one of the cases worth covering.
  Future<Rect> originFor(
    WidgetTester tester, {
    required Size buttonSize,
    Alignment alignment = Alignment.center,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: SizedBox(key: key, width: buttonSize.width, height: buttonSize.height),
        ),
      ),
    ));
    return shareOriginFrom(key.currentContext!);
  }

  group("the rect iOS is given", () {
    testWidgets("is the button's own position and size", (tester) async {
      final rect = await originFor(tester, buttonSize: const Size(120, 40));
      expect(rect.width, 120);
      expect(rect.height, 40);
    });

    testWidgets("is never empty", (tester) async {
      // An empty rect is the exact value iOS rejects.
      final rect = await originFor(tester, buttonSize: const Size(120, 40));
      expect(rect.isEmpty, isFalse);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });

    testWidgets("a zero-sized button still yields a usable rect", (tester) async {
      // A button that hasn't laid out, or has collapsed, must not take the
      // export down with it.
      final rect = await originFor(tester, buttonSize: Size.zero);
      expect(rect.isEmpty, isFalse);
      expect(rect, isNot(Rect.zero));
    });

    testWidgets("the fallback sits in the middle of the screen", (tester) async {
      final rect = await originFor(tester, buttonSize: Size.zero);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.center.dx, closeTo(screen.width / 2, 1));
      expect(rect.center.dy, closeTo(screen.height / 2, 1));
    });

    testWidgets("a button at the top-left is still on screen", (tester) async {
      final rect = await originFor(
        tester,
        buttonSize: const Size(80, 30),
        alignment: Alignment.topLeft,
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.isEmpty, isFalse);
    });

    testWidgets("a button at the bottom-right is still on screen", (tester) async {
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = await originFor(
        tester,
        buttonSize: const Size(80, 30),
        alignment: Alignment.bottomRight,
      );
      expect(rect.isEmpty, isFalse);
      // Overlapping the screen is the condition iOS actually checks.
      expect((Offset.zero & screen).overlaps(rect), isTrue);
    });
  });

  group("whatever is returned", () {
    testWidgets("always overlaps the screen", (tester) async {
      for (final size in [const Size(120, 40), Size.zero, const Size(1, 1)]) {
        final rect = await originFor(tester, buttonSize: size);
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(
          (Offset.zero & screen).overlaps(rect),
          isTrue,
          reason: "a $size button produced $rect, which iOS would refuse",
        );
      }
    });
  });
}

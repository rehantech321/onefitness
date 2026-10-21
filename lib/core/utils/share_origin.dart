import "package:flutter/material.dart";

/// Where the iOS share sheet should appear to come from.
///
/// On iOS the share sheet is a popover, and UIKit insists on knowing which
/// rectangle it points at. share_plus passes that straight through, so
/// omitting it throws rather than guessing:
///
///   PlatformException(error, sharePositionOrigin: argument must be set,
///   {{0, 0}, {0, 0}} must be non-zero and within coordinate space of
///   source view: {{0, 0}, {440, 956}})
///
/// which is what every export did on iPhone — the signed waiver PDF and
/// every CSV in Reports. Android ignores it entirely, so passing it always
/// is simpler than branching per platform.
///
/// Pass the context of the widget that was tapped: the sheet then rises
/// from the button, which is also what the person expects.
Rect shareOriginFrom(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && box.size.width > 0 && box.size.height > 0) {
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    // A rect outside the window is refused in the same way an empty one
    // is — a button scrolled off screen between the tap and this call
    // would otherwise take the export down with it.
    final screen = Offset.zero & MediaQuery.of(context).size;
    if (screen.overlaps(rect)) return rect;
  }

  // Nothing usable to point at: the middle of the screen, which is where
  // an unanchored sheet reads as coming from anyway. Deliberately not
  // Rect.zero — that is the exact value iOS rejects.
  final size = MediaQuery.of(context).size;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

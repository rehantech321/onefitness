import "dart:convert";
import "dart:typed_data";

import "package:flutter/foundation.dart" show compute;
import "package:flutter/material.dart";
import "package:image/image.dart" as img;
import "package:image_picker/image_picker.dart";
import "../widgets/photo_cropper_screen.dart";

/// Picks an image from the gallery, lets the user drag-to-reposition/
/// pinch-to-zoom it within a circular crop (PhotoCropperScreen, mirroring
/// ImageEditors.jsx's `PhotoCropper`), and returns the result as a
/// `data:image/jpeg;base64,...` URL — mirrors IntakeForm.jsx's own photo
/// handling (a plain FileReader-produced data URL saved straight into
/// profiles.photo_url), so this app doesn't need real object storage just
/// to let someone set a profile photo.
///
/// The crop step also keeps the payload small on its own (fixed 400×400
/// output, JPEG quality 85) — without that, a normal phone photo (several
/// MB) base64-encodes into a multi-MB string that has to round-trip through
/// Postgres and get re-parsed on every single sign-in/app-load afterward —
/// measured a real ~9s sign-in balloon to 35s+ with an unconstrained photo.
///
/// Returns null if the user cancels at either step, picking fails (denied
/// permission, etc.), or the picked file isn't decodable as an image —
/// nothing to surface as an error in any of those cases.
Future<String?> pickProfilePhotoDataUrl(BuildContext context) async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PhotoCropperScreen(bytes: bytes)),
    );
  } catch (_) {
    return null;
  }
}

/// Picks an image from the gallery and returns it as a compressed
/// `data:image/jpeg;base64,...` URL — no crop step (progress photos keep
/// their own aspect ratio, shown 3:4 in the grid), just a longest-edge-700
/// resize + JPEG quality 80, matching web's own `compressImage(file, 700)`
/// (ProgressPhotos.jsx) so a phone photo doesn't balloon client_records the
/// same way an uncompressed profile photo did — see pickProfilePhotoDataUrl.
///
/// Returns null if the user cancels, picking fails, or the file isn't
/// decodable as an image.
Future<String?> pickProgressPhotoDataUrl() async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return compute(_compressProgressPhoto, bytes);
  } catch (_) {
    return null;
  }
}

String? _compressProgressPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  const max = 700;
  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longest <= max
      ? decoded
      : (decoded.width >= decoded.height ? img.copyResize(decoded, width: max) : img.copyResize(decoded, height: max));
  final jpg = img.encodeJpg(resized, quality: 80);
  return "data:image/jpeg;base64,${base64Encode(jpg)}";
}

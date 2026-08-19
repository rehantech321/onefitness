import "package:flutter/material.dart";
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

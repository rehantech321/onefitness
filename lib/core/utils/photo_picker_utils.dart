import "dart:convert";
import "package:image/image.dart" as img;
import "package:image_picker/image_picker.dart";

/// Picks an image from the gallery and returns it as a `data:` URL —
/// mirrors IntakeForm.jsx's own photo handling (a plain FileReader-produced
/// data URL saved straight into profiles.photo_url), so this app doesn't
/// need real object storage just to let someone set a profile photo.
///
/// image_picker's own maxWidth/maxHeight/imageQuality params are NOT
/// reliably honored on the web platform (confirmed empirically — a picked
/// photo came back at its full original resolution despite those being
/// set), so this decodes and re-encodes the image itself via package:image
/// to guarantee a small payload. Without this, a normal phone photo (several
/// MB) base64-encodes into a multi-MB string that has to round-trip through
/// Postgres and get re-parsed on every single sign-in/app-load afterward —
/// measured a real ~9s sign-in balloon to 35s+ with an unconstrained photo.
///
/// Returns null if the user cancels, picking fails (denied permission,
/// etc.), or the picked file isn't decodable as an image — nothing to
/// surface as an error in any of those cases.
Future<String?> pickProfilePhotoDataUrl() async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    const maxDim = 400;
    final resized = (decoded.width > maxDim || decoded.height > maxDim)
        ? img.copyResize(decoded, width: decoded.width >= decoded.height ? maxDim : null, height: decoded.height > decoded.width ? maxDim : null)
        : decoded;
    final jpg = img.encodeJpg(resized, quality: 80);
    return "data:image/jpeg;base64,${base64Encode(jpg)}";
  } catch (_) {
    return null;
  }
}

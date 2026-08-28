import "dart:convert";
import "dart:typed_data";

/// Mirrors one entry in client.photos — an uploaded progress photo, stored
/// as a compressed `data:image/jpeg;base64,...` string directly in
/// client_records.data.photos (no real object storage — same approach the
/// app already uses for profile photos; see photo_picker_utils.dart).
class ProgressPhoto {
  const ProgressPhoto({required this.id, required this.date, required this.img});

  final String id;
  final String date; // ISO yyyy-MM-dd
  final String img; // data:image/jpeg;base64,...

  Uint8List get bytes => base64Decode(img.substring(img.indexOf(",") + 1));
}

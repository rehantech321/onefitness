import "dart:typed_data";

/// Mirrors one entry in client.photos — an uploaded progress photo. Kept as
/// in-memory bytes (not persisted to disk/network) for this UI-only pass.
class ProgressPhoto {
  const ProgressPhoto({required this.id, required this.date, required this.bytes});
  final String id;
  final String date; // ISO yyyy-MM-dd
  final Uint8List bytes;
}

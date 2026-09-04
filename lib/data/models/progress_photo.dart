import "dart:convert";
import "dart:typed_data";

/// Mirrors one entry in client.photos — an uploaded progress photo, stored
/// as a compressed `data:image/jpeg;base64,...` string directly in
/// client_records.data.photos (no real object storage — same approach the
/// app already uses for profile photos; see photo_picker_utils.dart).
class ProgressPhoto {
  const ProgressPhoto({required this.id, required this.date, required this.img, this.coachComment, this.coachCommentAt});

  final String id;
  final String date; // ISO yyyy-MM-dd
  final String img; // data:image/jpeg;base64,...

  /// A coach's note left on this specific photo (Notifications spec —
  /// "Coach comments on a progress photo"), shown to the client and
  /// emailed once on save. One comment per photo, editable — not a full
  /// thread.
  final String? coachComment;
  final String? coachCommentAt;

  Uint8List get bytes => base64Decode(img.substring(img.indexOf(",") + 1));

  ProgressPhoto copyWith({String? coachComment, String? coachCommentAt}) => ProgressPhoto(
        id: id,
        date: date,
        img: img,
        coachComment: coachComment ?? this.coachComment,
        coachCommentAt: coachCommentAt ?? this.coachCommentAt,
      );
}

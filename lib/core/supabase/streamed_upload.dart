import "dart:async";
import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

/// How far along an upload is, as a fraction from 0 to 1.
typedef UploadProgress = void Function(double fraction);

/// Uploads bytes to a Supabase Storage bucket, reporting progress as they go.
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// `storage_client` 2.8.0 has no progress callback on any of its upload
/// methods — it hands the whole body to `http` in one piece and returns when
/// the server answers. That is fine for a 200KB intake PDF and useless for a
/// 90MB video, where the coach is left watching a spinner for two minutes
/// with no way to tell a slow upload from a stalled one.
///
/// So this speaks to the same endpoint `uploadBinary` does, with the same
/// multipart body it builds, but streams the body itself in chunks and counts
/// them. Dart's HTTP client pulls from the stream only as the socket drains,
/// so the count tracks what has actually left the device rather than what has
/// been queued.
///
/// The request carries the signed-in user's token, so the bucket's RLS
/// policies apply exactly as they would to a normal `uploadBinary` call.
/// (A signed upload URL would also have worked, but those expire after one
/// minute — fine for a photo, a coin-flip for a video on gym wifi.)
///
/// [body] is consumed once and is never replayed, so this does not retry.
/// Taking a stream rather than bytes is what keeps a 120MB clip off the
/// heap: it can be piped from the file the coach picked straight to the
/// socket, and only [length] bytes of it are ever in memory at a time.
Future<void> uploadStreamWithProgress({
  required String bucket,
  required String path,
  required Stream<List<int>> body,
  required int length,
  required String contentType,
  UploadProgress? onProgress,
  bool upsert = false,
  http.Client? httpClient,
}) async {
  final storage = Supabase.instance.client.storage;
  final token = Supabase.instance.client.auth.currentSession?.accessToken;

  // `storage.headers` carries the apikey but is built once at startup, so its
  // Authorization is whatever was current then — the live user token comes
  // from the session.
  final headers = <String, String>{
    ...storage.headers,
    if (token != null) "Authorization": "Bearer $token",
    "x-upsert": upsert.toString(),
  };

  final framing = multipartFraming(
    boundary: "onefitness-${DateTime.now().microsecondsSinceEpoch}",
    contentType: contentType,
  );
  final total = framing.prologue.length + length + framing.epilogue.length;

  final client = httpClient ?? http.Client();
  try {
    final request = _StreamedBody(
      "POST",
      Uri.parse("${storage.url}/object/$bucket/$path"),
      multipartBodyStream(
        framing: framing,
        body: body,
        total: total,
        onProgress: onProgress,
      ),
      total,
    )..headers.addAll({
      ...headers,
      "Content-Type": "multipart/form-data; boundary=${framing.boundary}",
    });

    final response = await http.Response.fromStream(await client.send(request));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorageException(
        _messageFrom(response.body) ?? "Upload failed (${response.statusCode})",
        statusCode: "${response.statusCode}",
      );
    }
    // Only now is the upload real. Anything earlier was bytes in flight.
    onProgress?.call(1);
  } finally {
    if (httpClient == null) client.close();
  }
}

/// The bytes that go before and after the file in a storage upload body.
typedef MultipartFraming = ({String boundary, List<int> prologue, List<int> epilogue});

/// Builds the multipart framing `storage.uploadBinary` sends.
///
/// A `cacheControl` field, then the file as a part with an empty name and an
/// empty filename. Both oddities are the storage client's own — it notes the
/// request fails outright on a null filename — and the server reads the
/// object's content type off this part's header, which is why the type has to
/// be written here rather than only in the request headers.
///
/// This is deliberately byte-identical to what `http`'s MultipartRequest
/// produces for the same parts, down to the lowercase header names and the
/// content-type-before-content-disposition ordering it happens to use. Both
/// are arbitrary — a multipart parser is case-insensitive and does not care
/// about header order — but matching exactly means the body the storage API
/// already accepts from the library is the body it gets from here, and
/// exercise_video_test.dart holds the two together.
MultipartFraming multipartFraming({
  required String boundary,
  required String contentType,
}) => (
  boundary: boundary,
  prologue: utf8.encode(
    "--$boundary\r\n"
    'content-disposition: form-data; name="cacheControl"\r\n'
    "\r\n"
    "3600\r\n"
    "--$boundary\r\n"
    "content-type: $contentType\r\n"
    'content-disposition: form-data; name=""; filename=""\r\n'
    "\r\n",
  ),
  epilogue: utf8.encode("\r\n--$boundary--\r\n"),
);

/// The multipart body, counting the file's chunks as they pass through.
///
/// A generator rather than a pre-built stream because generators are pulled:
/// each chunk is taken from [body] when the socket is ready for it, which is
/// what makes the running total mean something.
Stream<List<int>> multipartBodyStream({
  required MultipartFraming framing,
  required Stream<List<int>> body,
  required int total,
  UploadProgress? onProgress,
}) async* {
  var sent = 0;
  var reported = 0.0;

  void report() {
    if (onProgress == null) return;
    // Held below 1 until the server has answered: a full bar next to a
    // request still in flight is the one reading a coach would act on, by
    // backing out of the screen a moment too early.
    final fraction = min(sent / total, 0.99);
    if (fraction - reported < 0.005) return;
    reported = fraction;
    onProgress(fraction);
  }

  yield framing.prologue;
  sent += framing.prologue.length;
  report();

  await for (final chunk in body) {
    yield chunk;
    sent += chunk.length;
    report();
  }

  yield framing.epilogue;
}

/// [uploadStreamWithProgress] for content already in memory — a photo, or
/// anything small enough that holding it is not the problem video is.
Future<void> uploadBinaryWithProgress({
  required String bucket,
  required String path,
  required Uint8List bytes,
  required String contentType,
  UploadProgress? onProgress,
  bool upsert = false,
  http.Client? httpClient,
}) => uploadStreamWithProgress(
  bucket: bucket,
  path: path,
  body: Stream.value(bytes),
  length: bytes.length,
  contentType: contentType,
  onProgress: onProgress,
  upsert: upsert,
  httpClient: httpClient,
);

/// Storage errors come back as `{"message": "..."}`; anything else is passed
/// over rather than shown raw.
String? _messageFrom(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded["message"] is String) {
      return decoded["message"] as String;
    }
  } catch (_) {
    // Not JSON.
  }
  return null;
}

/// A request whose body is a stream we own, so it can be counted on the way
/// out. `http`'s own MultipartRequest would hand the file over as one chunk.
class _StreamedBody extends http.BaseRequest {
  _StreamedBody(super.method, super.url, this._body, int length) {
    contentLength = length;
  }

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

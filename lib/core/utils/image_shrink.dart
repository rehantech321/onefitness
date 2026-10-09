import "dart:convert";

import "package:flutter/foundation.dart" show compute;
import "package:image/image.dart" as img;

/// Before/after photos are stored inside the coach's row as base64 text,
/// and every profile save sends them again. Older ones were picked at
/// 1600px (~700 KB each as text), which made a save with a single set about
/// 1.4 MB — large enough that phone uploads failed. Anything over
/// [maxBytes] is re-encoded down to [maxSide]px before it's sent; smaller
/// images, URLs and anything that won't decode go through untouched.
Future<String> shrinkDataUrlImage(String value, {int maxBytes = 260000, int maxSide = 900}) async {
  if (!value.startsWith("data:image") || value.length <= maxBytes) return value;
  final shrunk = await compute(_shrink, (value, maxSide));
  return shrunk ?? value;
}

String? _shrink((String, int) args) {
  final (value, maxSide) = args;
  try {
    final bytes = base64Decode(value.substring(value.indexOf(",") + 1));
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest <= maxSide
        ? decoded
        : (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxSide)
            : img.copyResize(decoded, height: maxSide));
    final jpg = img.encodeJpg(resized, quality: 80);
    final out = "data:image/jpeg;base64,${base64Encode(jpg)}";
    return out.length < value.length ? out : null;
  } catch (_) {
    return null;
  }
}

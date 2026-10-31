import "package:supabase_flutter/supabase_flutter.dart"
    show AuthException, FunctionException, PostgrestException;

/// Why a write failed, in words that point at the actual cause.
///
/// "Check your connection and try again" was the stock answer, and it is only
/// right when nothing reached the server. Whenever the server *did* answer —
/// and refused — that sentence sends someone to look in the one place the
/// problem is not.
///
/// The case that proved it: reordering Access Hub categories failed every
/// time, because `package_categories` had no UPDATE policy and the upsert's
/// `ON CONFLICT DO UPDATE` branch was refused with SQLSTATE 42501. The app
/// reported a connection problem on a perfectly good connection.
///
/// [whatFailed] is the action, already phrased as a sentence opener —
/// "Couldn't save the new order" — and this adds the reason.
String writeFailureMessage(Object error, {required String whatFailed}) {
  // Supabase Auth answered and said no. Its reasons are the ones people
  // actually hit — a rate limit, an address it won't send to, an email
  // provider that isn't set up — and every one of them was being reported as
  // a connection problem.
  if (error is AuthException) {
    final code = error.statusCode;
    final detail = error.message.trim();
    if (code == "429" || detail.toLowerCase().contains("rate limit")) {
      return "$whatFailed — too many requests in a short time. Wait a few minutes and try again.";
    }
    if (code == "422" || code == "400") {
      return detail.isEmpty ? "$whatFailed. Please check the address and try again." : "$whatFailed — $detail";
    }
    if (code == "500" || code == "502" || code == "503") {
      return "$whatFailed — the email service rejected it. This usually means the "
          "project's auth email provider isn't set up. The server's reason: "
          "${detail.isEmpty ? "none given" : detail}";
    }
    return detail.isEmpty ? "$whatFailed. Please try again." : "$whatFailed — $detail";
  }
  // An edge function that ran and returned an error.
  if (error is FunctionException) {
    final details = error.details;
    final reason = details is Map && details["error"] is String ? details["error"] as String : null;
    return reason == null || reason.isEmpty
        ? "$whatFailed. Please try again."
        : "$whatFailed — $reason";
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case "42501":
        return "$whatFailed — this account doesn't have permission to make that change. "
            "If it should, the gym owner can grant it.";
      case "23505":
        return "$whatFailed — something with that name already exists.";
      case "23503":
        return "$whatFailed — it points at something that no longer exists.";
      case "23514":
        return "$whatFailed — that value isn't one this field accepts.";
    }
    // Some other refusal. It still reached the server, so the one thing not
    // to say is that the network is at fault.
    final detail = error.message.trim();
    return detail.isEmpty ? "$whatFailed. Please try again." : "$whatFailed — $detail";
  }
  // No structured error: a timeout, DNS, a dropped socket. Now the stock
  // advice is the right advice.
  return "$whatFailed — check your connection and try again.";
}

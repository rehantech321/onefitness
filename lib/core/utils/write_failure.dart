import "package:supabase_flutter/supabase_flutter.dart" show PostgrestException;

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

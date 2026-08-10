import "package:supabase_flutter/supabase_flutter.dart";

/// Turns a sign-in exception into a message the user can actually act on,
/// instead of always showing "Incorrect email or password" — which used to
/// mask network/DNS failures (e.g. a missing Android INTERNET permission)
/// AND real bugs (a data-parsing crash while loading post-signin data)
/// behind a misleading credentials error that sends the user chasing the
/// wrong fix.
String authErrorMessage(Object e) {
  if (e is AuthRetryableFetchException) {
    return "Can't reach the server — check your internet connection and try again.";
  }
  if (e is AuthApiException) {
    return "Incorrect email or password.";
  }
  final text = e.toString();
  if (text.contains("SocketException") || text.contains("Failed host lookup") || text.contains("ClientException")) {
    return "Can't reach the server — check your internet connection and try again.";
  }
  if (e is Exception) {
    // App-thrown Exceptions (e.g. "This account isn't set up as a coach.")
    // carry their own real, actionable message — show it as-is.
    return text.replaceFirst("Exception: ", "");
  }
  // Anything else (a genuine bug — TypeError, StateError, ...) is not a
  // credentials problem; show it plainly instead of lying about why sign-in
  // failed.
  return "Something went wrong signing in: $text";
}

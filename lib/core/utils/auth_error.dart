import "package:supabase_flutter/supabase_flutter.dart";

/// Turns a sign-in exception into a message the user can actually act on,
/// instead of always showing "Incorrect email or password" — which used to
/// mask network/DNS failures (e.g. a missing Android INTERNET permission)
/// behind a misleading credentials error.
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
  return "Incorrect email or password.";
}

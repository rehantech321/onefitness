/// What to tell someone whose save failed. "Check your connection" used to
/// be shown for every failure, so a rejected word in a bio or a duplicate
/// phone number looked like a network problem and couldn't be fixed.
String saveErrorMessage(Object e) {
  final raw = e.toString();
  if (raw.contains("objectionable_content: bio")) {
    return "Your bio contains words that aren't allowed. Please edit it and try again.";
  }
  if (raw.contains("objectionable_content: name")) {
    return "That name contains words that aren't allowed. Please edit it and try again.";
  }
  final lower = raw.toLowerCase();
  if (lower.contains("socketexception") ||
      lower.contains("clientexception") ||
      lower.contains("connection") ||
      lower.contains("timed out") ||
      lower.contains("failed host lookup")) {
    return "Couldn't reach the server — check your connection and try again.";
  }
  final message = raw
      .replaceFirst("Exception: ", "")
      .replaceFirst(RegExp(r"^PostgrestException\(message: "), "")
      .split(", code:")
      .first;
  return "Couldn't save: $message";
}

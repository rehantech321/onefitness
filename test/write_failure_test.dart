import "package:flutter_test/flutter_test.dart";
import "package:supabase_flutter/supabase_flutter.dart"
    show AuthException, PostgrestException;

import "package:onefitness/core/utils/write_failure.dart";

/// Telling someone what actually went wrong.
///
/// Written after reordering Access Hub categories reported "check your
/// connection" on a working connection — the real cause was a missing UPDATE
/// policy, refused by Postgres with SQLSTATE 42501. The failure was in the
/// database and the message pointed at the wifi.
void main() {
  const what = "Couldn't save the new order";

  test("a permission refusal says so, and never blames the network", () {
    final msg = writeFailureMessage(
      PostgrestException(message: "new row violates row-level security policy", code: "42501"),
      whatFailed: what,
    );
    expect(msg, startsWith(what));
    expect(msg, contains("permission"));
    expect(msg.toLowerCase(), isNot(contains("connection")));
  });

  test("a duplicate is reported as a duplicate", () {
    final msg = writeFailureMessage(
      PostgrestException(message: "duplicate key value", code: "23505"),
      whatFailed: "Couldn't add that category",
    );
    expect(msg, contains("already exists"));
    expect(msg.toLowerCase(), isNot(contains("connection")));
  });

  test("a broken reference and a rejected value each get their own reason", () {
    expect(
      writeFailureMessage(PostgrestException(message: "fk", code: "23503"), whatFailed: what),
      contains("no longer exists"),
    );
    expect(
      writeFailureMessage(PostgrestException(message: "check", code: "23514"), whatFailed: what),
      contains("isn't one this field accepts"),
    );
  });

  test("an unrecognised server error still doesn't blame the network", () {
    // The server answered. Whatever it said, the connection worked.
    final msg = writeFailureMessage(
      PostgrestException(message: "something specific went wrong", code: "XX000"),
      whatFailed: what,
    );
    expect(msg, contains("something specific went wrong"));
    expect(msg.toLowerCase(), isNot(contains("check your connection")));
  });

  test("a server error with no message still reads as a sentence", () {
    final msg = writeFailureMessage(
      PostgrestException(message: "   ", code: "XX000"),
      whatFailed: what,
    );
    expect(msg, "$what. Please try again.");
  });

  group("Supabase Auth refusals", () {
    const sending = "Couldn't send the reset email";

    test("a rate limit says to wait, not to check the wifi", () {
      // What a project on Supabase's built-in email hits first: a handful of
      // auth emails an hour, then 429.
      final msg = writeFailureMessage(
        const AuthException("email rate limit exceeded", statusCode: "429"),
        whatFailed: sending,
      );
      expect(msg, contains("Wait a few minutes"));
      expect(msg.toLowerCase(), isNot(contains("connection")));
    });

    test("a rate limit is recognised from the text even without a 429", () {
      final msg = writeFailureMessage(
        const AuthException("For security purposes you have exceeded the rate limit"),
        whatFailed: sending,
      );
      expect(msg, contains("Wait a few minutes"));
    });

    test("a 500 points at the email provider and quotes the server", () {
      // The case here: auth email isn't configured, so nothing is sent.
      final msg = writeFailureMessage(
        const AuthException("Error sending recovery email", statusCode: "500"),
        whatFailed: sending,
      );
      expect(msg, contains("email service"));
      expect(msg, contains("Error sending recovery email"));
      expect(msg.toLowerCase(), isNot(contains("check your connection")));
    });

    test("a rejected address is passed through as given", () {
      final msg = writeFailureMessage(
        const AuthException("Unable to validate email address", statusCode: "400"),
        whatFailed: sending,
      );
      expect(msg, contains("Unable to validate email address"));
    });

    test("an auth error with no message still reads as a sentence", () {
      expect(
        writeFailureMessage(const AuthException("  "), whatFailed: sending),
        "$sending. Please try again.",
      );
    });
  });

  test("an actual network failure keeps the advice that fits it", () {
    // No structured error at all — a timeout or a dropped socket. Here the
    // stock advice is the correct advice.
    final msg = writeFailureMessage(Exception("SocketException: failed host lookup"), whatFailed: what);
    expect(msg, contains("check your connection"));
  });
}

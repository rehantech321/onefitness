import "dart:io" show Platform;
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "../supabase/supabase_service.dart";

/// Background/terminated-state handler. Must be a top-level function — the
/// OS spins up a separate Dart isolate to run it, so anything captured from
/// the app's own isolate is unavailable here.
///
/// Deliberately does nothing: a notification with a `notification` block is
/// already displayed by the system before this runs, and every action the
/// app needs happens when it's next opened. It exists because registering a
/// background handler is what stops FCM dropping messages that arrive while
/// the app isn't running.
@pragma("vm:entry-point")
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Device-token lifecycle for push notifications.
///
/// The server half of this (register-device-token, send-push, and the
/// triggers that call them) has been in place for a while, but nothing ever
/// arrived because no token was produced: without the Firebase SDK the app
/// never asked the OS for one, so `device_tokens` stayed empty and every
/// send had nowhere to go. This is the piece that closes that gap.
class PushService {
  static bool _initialised = false;

  /// Safe to call before sign-in and safe to call twice. Initialises
  /// Firebase and registers the background handler, but does NOT ask for
  /// permission — that's [registerForCurrentUser], so the OS prompt appears
  /// when the person is signed in and the request has visible context,
  /// rather than on first launch before they know what the app is.
  static Future<void> init() async {
    if (_initialised || kIsWeb) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      _initialised = true;
    } catch (e) {
      // Push is a nice-to-have: a misconfigured or missing Firebase setup
      // must never stop the app starting.
      debugPrint("PushService.init failed: $e");
    }
  }

  /// Asks for notification permission (Android 13+ and iOS both require it)
  /// and registers this device against the signed-in user. Call after
  /// sign-in, and on resume so a rotated token doesn't go stale.
  static Future<void> registerForCurrentUser() async {
    if (!_initialised || kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // On iOS the APNs token can lag behind registration; without it FCM
      // returns null rather than a token. Absent APNs config this simply
      // stays null and we skip, instead of throwing.
      if (!kIsWeb && Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        if (apns == null) {
          debugPrint("PushService: no APNs token yet — skipping registration.");
          return;
        }
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _send(token);

      // Tokens rotate (reinstall, restore, Firebase's own rotation). Without
      // this the server keeps pushing to a dead token and the user silently
      // stops receiving anything.
      messaging.onTokenRefresh.listen(_send);
    } catch (e) {
      debugPrint("PushService.registerForCurrentUser failed: $e");
    }
  }

  static Future<void> _send(String token) async {
    try {
      await SupabaseService.registerDeviceToken(
        token,
        kIsWeb ? "web" : (Platform.isIOS ? "ios" : "android"),
      );
    } catch (e) {
      debugPrint("PushService: couldn't register token: $e");
    }
  }
}

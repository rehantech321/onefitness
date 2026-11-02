import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Light or dark, and whether the phone decides.
///
/// Stored on the device rather than on the profile: a theme is a property of
/// the screen you're looking at, not of the account. Someone signed in on a
/// bright gym floor and a dark bedroom wants different answers on each, and
/// a coach using a shared tablet shouldn't reset it for the next person.
///
/// Defaults to [ThemeMode.system], so the app matches whatever the phone is
/// already set to on first launch instead of overriding it.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = "themeMode";

  @override
  ThemeMode build() {
    // main() reads the stored choice before the first frame and seeds it
    // here, so the app opens straight into the right palette.
    final seeded = ref.read(initialThemeModeProvider);
    if (seeded != null) return seeded;

    // No seed (a test, or startup couldn't read storage): fall back to the
    // phone's setting and correct ourselves when the preference arrives.
    _restore();
    return ThemeMode.system;
  }

  /// The stored choice, or null if there isn't one.
  ///
  /// Called before runApp so the first frame is already right. Opening on
  /// ThemeMode.system and correcting a frame later means someone whose phone
  /// is light but who chose Dark watches the app flash white on every cold
  /// start — most visible on the sign-in screen, which is the first thing
  /// drawn and has a photo behind it.
  static Future<ThemeMode?> readStored() async {
    try {
      return _fromName((await SharedPreferences.getInstance()).getString(_key));
    } catch (_) {
      return null;
    }
  }

  Future<void> _restore() async {
    final restored = await readStored();
    if (restored != null && restored != state) state = restored;
  }

  Future<void> set(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // The theme still changed for this session; it just won't be
      // remembered. Not worth interrupting anyone over.
    }
  }

  static ThemeMode? _fromName(String? name) => switch (name) {
    "light" => ThemeMode.light,
    "dark" => ThemeMode.dark,
    "system" => ThemeMode.system,
    _ => null,
  };
}

/// The stored choice, read before runApp and injected by an override there.
///
/// Null means "nothing stored, or we couldn't read it" — the notifier then
/// falls back to the phone's setting, which is also what tests get.
final initialThemeModeProvider = Provider<ThemeMode?>((_) => null);

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// What to show for the current selection.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => "Light",
  ThemeMode.dark => "Dark",
  ThemeMode.system => "Match phone",
};

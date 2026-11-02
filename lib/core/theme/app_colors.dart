import "package:flutter/material.dart";

/// One complete set of colour tokens.
///
/// The names come from the web app's `src/constants/theme.js` and the dark
/// values are its originals, unchanged — so a screen written against the web
/// source still lines up. [AppPalette.light] is this app's own.
class AppPalette {
  const AppPalette({
    required this.gold,
    required this.goldDim,
    required this.onGold,
    required this.danger,
    required this.warning,
    required this.info,
    required this.bg,
    required this.card,
    required this.line,
    required this.txt,
    required this.mute,
    required this.calendarDone,
    required this.calendarMissed,
    required this.drawerBg,
    required this.bottomBarBg,
    required this.errorText,
    required this.statusNew,
    required this.statusNewBorder,
    required this.statusRed,
    required this.statusYellow,
    required this.statusGreen,
    required this.isDark,
  });

  final Color gold;
  final Color goldDim;
  final Color onGold;
  final Color danger;
  final Color warning;
  final Color info;
  final Color bg;
  final Color card;
  final Color line;
  final Color txt;
  final Color mute;
  final Color calendarDone;
  final Color calendarMissed;
  final Color drawerBg;
  final Color bottomBarBg;
  final Color errorText;
  final Color statusNew;
  final Color statusNewBorder;
  final Color statusRed;
  final Color statusYellow;
  final Color statusGreen;
  final bool isDark;

  /// The app as it has always looked. Values unchanged from the web port.
  static const dark = AppPalette(
    isDark: true,
    gold: Color(0xFFD9D9D9),
    goldDim: Color(0xFF5A5A5C),
    onGold: Colors.black,
    danger: Color(0xFFE05555),
    warning: Color(0xFFD68A4F),
    info: Color(0xFF4F8DD6),
    bg: Color(0xFF000000),
    card: Color(0xFF161617),
    line: Color(0xFF2A2A2C),
    txt: Color(0xFFFFFFFF),
    mute: Color(0xFF8B8A85),
    calendarDone: Color(0xFF4EA863),
    calendarMissed: Color(0xFFC0564F),
    drawerBg: Color(0xFF0A0A0A),
    bottomBarBg: Color(0xFF000000),
    errorText: Color(0xFFC97F7F),
    statusNew: Color(0xFFE9E7E0),
    statusNewBorder: Color(0xFF9A988F),
    statusRed: Color(0xFFC0564F),
    statusYellow: Color(0xFFD9A531),
    statusGreen: Color(0xFF4EC97A),
  );

  /// Light mode.
  ///
  /// Not an inversion of [dark] — a straight invert gives pure-white pages
  /// with near-white cards that no longer read as raised, and a #D9D9D9
  /// accent that vanishes entirely. So:
  ///
  ///   * the page is a soft off-white and cards are pure white, keeping the
  ///     card/page separation the dark theme gets from #000 vs #161617;
  ///   * [gold] — the accent on every primary button, selected chip and
  ///     highlight — becomes near-black with white content, since the dark
  ///     theme's light-grey-on-black would be invisible here;
  ///   * the status and calendar colours are darkened rather than reused,
  ///     because shades picked to glow on black go muddy on white.
  static const light = AppPalette(
    isDark: false,
    gold: Color(0xFF1C1C1E),
    goldDim: Color(0xFFB9B9BD),
    onGold: Colors.white,
    danger: Color(0xFFC0392B),
    warning: Color(0xFFB4701F),
    info: Color(0xFF2F6FB5),
    bg: Color(0xFFF4F4F6),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFD9D9DE),
    txt: Color(0xFF111113),
    mute: Color(0xFF6B6B72),
    calendarDone: Color(0xFF2E7D4F),
    calendarMissed: Color(0xFFB03A33),
    drawerBg: Color(0xFFFFFFFF),
    bottomBarBg: Color(0xFFFFFFFF),
    errorText: Color(0xFFB3261E),
    statusNew: Color(0xFF4A4A50),
    statusNewBorder: Color(0xFF8A8A92),
    statusRed: Color(0xFFB03A33),
    statusYellow: Color(0xFFB4860F),
    statusGreen: Color(0xFF2E9E57),
  );
}

/// Colour tokens for the active theme.
///
/// These were `static const` and are now getters over a swappable palette.
/// That one change is what makes light mode possible without rewriting the
/// 2,800-odd call sites: every `AppColors.bg` in the app still reads the
/// same, it just resolves at runtime instead of compile time. The cost is
/// that a widget using one can no longer be `const` — which the compiler
/// enforces, so nothing can be left behind on a screen nobody reopened.
///
/// [apply] is called once, from the root, before the tree builds. It's
/// global mutable state, which is normally worth avoiding, but the
/// alternative — threading a BuildContext lookup through all 170 files —
/// buys nothing here: there is exactly one theme for the whole app, and it
/// changes only when the user changes it.
class AppColors {
  AppColors._();

  static AppPalette _active = AppPalette.dark;

  static AppPalette get palette => _active;

  /// Returns true when the palette actually changed, so the caller can skip
  /// a rebuild it doesn't need.
  static bool apply(AppPalette next) {
    if (identical(_active, next)) return false;
    _active = next;
    return true;
  }

  static Color get gold => _active.gold;
  static Color get goldDim => _active.goldDim;

  /// Completed sets and success states. Shares [gold] by design.
  static Color get grn => _active.gold;
  static Color get onGold => _active.onGold;

  static Color get danger => _active.danger;
  static Color get warning => _active.warning;
  static Color get success => _active.gold;
  static Color get info => _active.info;

  static Color get bg => _active.bg;
  static Color get card => _active.card;
  static Color get line => _active.line;
  static Color get txt => _active.txt;
  static Color get mute => _active.mute;

  static Color get calendarDone => _active.calendarDone;
  static Color get calendarMissed => _active.calendarMissed;
  static Color get calendarUpcoming => _active.gold;

  static Color get drawerBg => _active.drawerBg;
  static Color get bottomBarBg => _active.bottomBarBg;

  static Color get errorText => _active.errorText;

  static Color get statusNew => _active.statusNew;
  static Color get statusNewBorder => _active.statusNewBorder;
  static Color get statusRed => _active.statusRed;
  static Color get statusYellow => _active.statusYellow;
  static Color get statusGreen => _active.statusGreen;
}

/// The web app's single-column layout is centered and capped at this width
/// everywhere (top bars, content, fixed bottom bars). On phone widths this
/// has no effect; it only matters on tablet/desktop.
const double kPageMaxWidth = 1440;

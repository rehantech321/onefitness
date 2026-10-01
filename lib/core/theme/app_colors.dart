import "package:flutter/material.dart";

/// Color tokens ported 1:1 from the web app's `src/constants/theme.js`.
/// Keep names and hex values identical so future screens stay in sync
/// with the source of truth without re-deriving them.
class AppColors {
  AppColors._();

  // Accent (formerly the brand green). Buttons, badges and highlighted
  // states use a light grey fill with black content — see [onGold].
  static const gold = Color(0xFFD9D9D9);
  static const goldDim = Color(0xFF5A5A5C);
  static const grn = gold; // completed sets, success states
  /// Text/icon color for anything drawn on a [gold] fill.
  static const onGold = Colors.black;

  // Semantic status colors
  static const danger = Color(0xFFE05555);
  static const warning = Color(0xFFD68A4F);
  static const success = grn;
  static const info = Color(0xFF4F8DD6);

  static const bg = Color(0xFF000000);
  static const card = Color(0xFF161617);
  static const line = Color(0xFF2A2A2C);
  static const txt = Color(0xFFFFFFFF);
  static const mute = Color(0xFF8B8A85);

  // Calendar dot / status colors used on the client dashboard
  // Kept green: a grey "done" would be indistinguishable from "upcoming".
  static const calendarDone = Color(0xFF4EA863);
  static const calendarMissed = Color(0xFFC0564F);
  static const calendarUpcoming = gold;

  // Drawer surface (slightly lighter than page bg)
  static const drawerBg = Color(0xFF0A0A0A);
  static const bottomBarBg = Color(0xFF000000);

  static const errorText = Color(0xFFC97F7F);

  // StatusDot / client progress-status system (lib/helpers.js STATUS_META)
  static const statusNew = Color(0xFFE9E7E0);
  static const statusNewBorder = Color(0xFF9A988F);
  static const statusRed = Color(0xFFC0564F);
  static const statusYellow = Color(0xFFD9A531);
  // Traffic-light status stays green; grey would clash with statusNew.
  static const statusGreen = Color(0xFF4EC97A);
}

/// The web app's single-column layout is centered and capped at this width
/// everywhere (top bars, content, fixed bottom bars). On phone widths this
/// has no effect; it only matters on tablet/desktop.
const double kPageMaxWidth = 1440;

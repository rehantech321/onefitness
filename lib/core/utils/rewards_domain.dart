import "package:flutter/material.dart";
import "../theme/app_colors.dart";

class WayToEarn {
  const WayToEarn({required this.key, required this.points, required this.label, required this.desc});
  final String key;
  final String points; // usually an int as string, "1–5" for discretionary
  final String label;
  final String desc;
}

/// Mirrors src/constants/domain.js `WAYS_TO_EARN`.
const kWaysToEarn = <WayToEarn>[
  WayToEarn(key: "challenge_participation", points: "1", label: "Join & complete a challenge", desc: "Earn 1 point just for participating in any gym challenge."),
  WayToEarn(key: "challenge_2nd", points: "3", label: "Place 2nd in a challenge", desc: "Finish runner-up on the leaderboard when a challenge ends."),
  WayToEarn(key: "challenge_1st", points: "5", label: "Win a challenge", desc: "Finish 1st on the leaderboard when a challenge ends."),
  WayToEarn(key: "workout_streak", points: "3", label: "Log 3 weeks of workouts in a row", desc: "Earn 3 points every 3 consecutive weeks you log your own workouts."),
  WayToEarn(key: "progress_photo", points: "1", label: "Log a progress photo", desc: "Earn 1 point for logging a progress photo this month."),
  WayToEarn(key: "measurement", points: "1", label: "Log a measurement", desc: "Earn 1 point for logging a body measurement this month."),
  WayToEarn(key: "referral", points: "3", label: "Refer a friend", desc: "Earn 3 points when someone you refer completes their first purchase."),
  WayToEarn(key: "discretionary_grant", points: "1–5", label: "Coach recognition", desc: "Your coach or the owner can award bonus points for extra effort."),
];

const kRewardMinRedeemPoints = 10;
const kRewardMaxRedeemPoints = 40;
const kRewardExpiringSoonDays = 60;

/// Mirrors src/constants/theme.js `SOURCE_LABELS` (rewards/LedgerTable.jsx).
const kSourceLabels = {
  "challenge_participation": "Challenge — participated",
  "challenge_1st": "Challenge — 1st place",
  "challenge_2nd": "Challenge — 2nd place",
  "referral": "Referred a friend",
  "workout_streak": "3-week workout streak",
  "progress_photo": "Progress photo logged",
  "measurement": "Measurement logged",
  "discretionary_grant": "Coach/owner grant",
  "redemption_checkout": "Redeemed at checkout",
  "redemption_balance": "Redeemed for account credit",
  "void_grant": "Voided",
  "referral_clawback": "Referral clawed back",
  "expiry_sweep": "Expired",
  "owner_deduction": "Deducted by owner",
  "merit_badge_bonus": "Merit Badge bonus — 3+ badges earned",
  "merit_badge_points": "Merit Badge points (4+ active badges)",
};

String sourceLabel(String source) => kSourceLabels[source] ?? source;

class PointsBannerMeta {
  const PointsBannerMeta({required this.emoji, required this.color, required this.bg, required this.border});
  final String emoji;
  final Color color;
  final Color bg;
  final Color border;
}

/// Mirrors `POINTS_BANNER_META`.
const kPointsBannerExpiring = PointsBannerMeta(
  emoji: "\u{23F3}",
  color: AppColors.warning,
  bg: Color(0x1AD68A4F),
  border: Color(0xFF8A6A2F),
);

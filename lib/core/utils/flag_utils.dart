import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "../../data/models/trainer_note.dart";

class FlagMeta {
  const FlagMeta({required this.emoji, required this.label, required this.shortLabel, required this.desc, required this.color, required this.alertMsg});
  final String emoji;
  final String label;
  final String shortLabel;
  final String desc;
  final Color color;
  final String alertMsg;
}

/// Mirrors constants/domain.js `FLAG_META`. "payment" isn't a manually
/// chosen coach note — it's derived from ClientInfo.hasOutstandingBalance.
const kFlagMeta = {
  "payment": FlagMeta(
    emoji: "\u{1F4B3}",
    label: "Payment Failed",
    shortLabel: "PAYMENT FAILED",
    desc: "Outstanding balance",
    color: Color(0xFFB06FD1),
    alertMsg: "\u{1F4B3} PAYMENT FAILED – Outstanding balance, check-in blocked until paid",
  ),
  "red": FlagMeta(
    emoji: "\u{1F534}",
    label: "Red Flag",
    shortLabel: "RED FLAG",
    desc: "Critical Attention",
    color: AppColors.danger,
    alertMsg: "\u{1F534} RED FLAG – Review Trainer Notes Before Training",
  ),
  "yellow": FlagMeta(
    emoji: "\u{1F7E1}",
    label: "Yellow Flag",
    shortLabel: "YELLOW FLAG",
    desc: "Injury / Temp Caution",
    color: AppColors.warning,
    alertMsg: "\u{1F7E1} CAUTION – Check Trainer Notes",
  ),
  "blue": FlagMeta(
    emoji: "\u{1F535}",
    label: "Blue Flag",
    shortLabel: "BLUE FLAG",
    desc: "Coaching Reminder",
    color: AppColors.info,
    alertMsg: "\u{1F535} Coaching note on file",
  ),
};

/// Mirrors FLAG_ORDER — precedence when several active notes exist.
const kFlagOrder = ["red", "yellow", "blue"];

List<TrainerNote> getActiveNotes(ClientRecord record) => record.trainerNotes.where((n) => n.status == "active").toList();

/// Mirrors intakeHelpers.js `getHighestFlag` — payment always wins (blocks
/// check-in), otherwise the highest-precedence active coach note.
String? getHighestFlag(ClientRecord record, [ClientInfo? rosterInfo]) {
  if (rosterInfo?.hasOutstandingBalance == true) return "payment";
  final active = getActiveNotes(record);
  for (final f in kFlagOrder) {
    if (active.any((n) => n.flag == f)) return f;
  }
  return null;
}

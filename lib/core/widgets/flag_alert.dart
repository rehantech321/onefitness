import "package:flutter/material.dart";
import "../utils/flag_utils.dart";

/// Mirrors FlagAlert.jsx — a prominent banner (or compact pill) for the
/// highest-priority active coach flag on a client.
class FlagAlert extends StatelessWidget {
  const FlagAlert({super.key, required this.flag, this.compact = false});

  final String? flag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (flag == null) return const SizedBox.shrink();
    final m = kFlagMeta[flag]!;
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: m.color.withValues(alpha: 0.12),
          border: Border.all(color: m.color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          "${m.emoji} ${m.shortLabel}",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: m.color, letterSpacing: 0.5),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.12),
        border: Border.all(color: m.color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(m.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(m.alertMsg, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: m.color))),
        ],
      ),
    );
  }
}

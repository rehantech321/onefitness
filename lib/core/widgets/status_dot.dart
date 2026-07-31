import "package:flutter/material.dart";
import "../theme/app_colors.dart";

enum ClientStatus { newClient, red, yellow, green }

class StatusMeta {
  const StatusMeta({required this.color, required this.border, required this.label, required this.desc});
  final Color color;
  final Color border;
  final String label;
  final String desc;
}

/// Mirrors lib/helpers.js `STATUS_META` — the four-state client progress system.
const Map<ClientStatus, StatusMeta> kStatusMeta = {
  ClientStatus.newClient: StatusMeta(
    color: AppColors.statusNew,
    border: AppColors.statusNewBorder,
    label: "New client",
    desc: "No sessions logged yet",
  ),
  ClientStatus.red: StatusMeta(
    color: AppColors.statusRed,
    border: AppColors.statusRed,
    label: "Not logging",
    desc: "No session logged in the last 7 days",
  ),
  ClientStatus.yellow: StatusMeta(
    color: AppColors.statusYellow,
    border: AppColors.statusYellow,
    label: "Holding steady",
    desc: "Logging, but no recent improvement",
  ),
  ClientStatus.green: StatusMeta(
    color: AppColors.statusGreen,
    border: AppColors.statusGreen,
    label: "Making progress",
    desc: "Improved within the last 7 days",
  ),
};

/// Mirrors components/ui/StatusDot.jsx.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 10});

  final ClientStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final meta = kStatusMeta[status]!;
    return Tooltip(
      message: meta.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: meta.color,
          border: Border.all(color: AppColors.bg, width: 1),
          boxShadow: [BoxShadow(color: meta.border, blurRadius: 0, spreadRadius: 1)],
        ),
      ),
    );
  }
}

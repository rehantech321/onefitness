import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "attendance_reports.dart";
import "date_range_filter.dart";
import "financial_reports.dart";
import "payroll_reports.dart";
import "profitability_report.dart";

class _ReportDef {
  const _ReportDef(this.key, this.title, this.description, this.icon, this.defaultPreset, this.builder);
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final String defaultPreset;
  final Widget Function(ReportRange) builder;
}

class _Category {
  const _Category(this.title, this.reports);
  final String title;
  final List<_ReportDef> reports;
}

final _catalog = [
  _Category("Financial", [
    _ReportDef("sales", "Itemized Sales", "Every real charge in range", LucideIcons.receipt, "month", (r) => ItemizedSalesReport(range: r)),
    _ReportDef("realtime", "Real-Time Charges", "Recent charges with refund/waive", LucideIcons.creditCard, "today", (r) => RealTimeChargesReport(range: r)),
    _ReportDef("projected", "Projected Revenue", "Active members by plan", LucideIcons.trendingUp, "month", (r) => ProjectedRevenueReport(range: r)),
  ]),
  _Category("Visit & Utilization", [
    _ReportDef("attendance", "Attendance Summary", "Sessions by attendance status", LucideIcons.calendarCheck, "month", (r) => AttendanceSummaryReport(range: r)),
    _ReportDef("utilization", "Session Utilization", "Booked vs. available slots", LucideIcons.percent, "week", (r) => SessionUtilizationReport(range: r)),
  ]),
  _Category("Trainer & Payroll", [
    _ReportDef("hours", "Staff Hours", "Estimated hours per coach", LucideIcons.clock, "month", (r) => StaffHoursReport(range: r)),
    _ReportDef("commissions", "Service Commissions", "Commission earned per coach", LucideIcons.badgePercent, "month", (r) => ServiceCommissionsReport(range: r)),
    _ReportDef("payroll", "Payroll Summary", "Pay owed per coach", LucideIcons.wallet, "month", (r) => PayrollSummaryReport(range: r)),
  ]),
  _Category("Profitability", [
    _ReportDef("profitability", "Revenue vs. Payroll", "Net profit and margin", LucideIcons.scale, "month", (r) => RevenueVsPayrollReport(range: r)),
  ]),
];

/// Mirrors ReportsHub.jsx (owner-only) — a catalog of reports grouped by
/// category, each opening full-screen with a shared date-range filter. No
/// favorites/search/CSV export in this trimmed build.
class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  _ReportDef? _open;
  ReportRange? _range;

  @override
  Widget build(BuildContext context) {
    if (_open != null) {
      final range = _range ?? presetRange(_open!.defaultPreset);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackBar(onBack: () => setState(() => _open = null), title: _open!.title),
            const SizedBox(height: 4),
            Text(_open!.description, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
            const SizedBox(height: 12),
            DateRangeFilter(range: range, onChange: (r) => setState(() => _range = r)),
            const SizedBox(height: 14),
            _open!.builder(range),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cat in _catalog) ...[
            SectionLabel(cat.title),
            ...cat.reports.map((r) => AppCard(
                  onTap: () => setState(() {
                    _open = r;
                    _range = null;
                  }),
                  child: Row(
                    children: [
                      Icon(r.icon, size: 18, color: AppColors.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(r.description, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

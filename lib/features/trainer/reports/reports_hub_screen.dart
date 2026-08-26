import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "attendance_reports.dart";
import "date_range_filter.dart";
import "financial_reports.dart";
import "payroll_reports.dart";
import "profitability_report.dart";
import "rewards_report.dart";

class _ReportDef {
  const _ReportDef(
    this.key,
    this.title,
    this.description,
    this.icon,
    this.defaultPreset,
    this.builder,
  );
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
    _ReportDef(
      "sales",
      "Itemized Sales",
      "Every real charge in range",
      LucideIcons.receipt,
      "month",
      (r) => ItemizedSalesReport(range: r),
    ),
    _ReportDef(
      "realtime",
      "Real-Time Charges",
      "Recent charges with refund/waive",
      LucideIcons.creditCard,
      "today",
      (r) => RealTimeChargesReport(range: r),
    ),
    _ReportDef(
      "projected",
      "Projected Revenue",
      "Active members by plan",
      LucideIcons.trendingUp,
      "month",
      (r) => ProjectedRevenueReport(range: r),
    ),
  ]),
  _Category("Visit & Utilization", [
    _ReportDef(
      "attendance",
      "Attendance Summary",
      "Sessions by attendance status",
      LucideIcons.calendarCheck,
      "month",
      (r) => AttendanceSummaryReport(range: r),
    ),
    _ReportDef(
      "utilization",
      "Session Utilization",
      "Booked vs. available slots",
      LucideIcons.percent,
      "week",
      (r) => SessionUtilizationReport(range: r),
    ),
  ]),
  _Category("Trainer & Payroll", [
    _ReportDef(
      "hours",
      "Staff Hours",
      "Estimated hours per coach",
      LucideIcons.clock,
      "month",
      (r) => StaffHoursReport(range: r),
    ),
    _ReportDef(
      "commissions",
      "Service Commissions",
      "Commission earned per coach",
      LucideIcons.badgePercent,
      "month",
      (r) => ServiceCommissionsReport(range: r),
    ),
    _ReportDef(
      "payroll",
      "Payroll Summary",
      "Pay owed per coach",
      LucideIcons.wallet,
      "month",
      (r) => CoachMeritBadgeAutoFinalize(child: PayrollSummaryReport(range: r)),
    ),
    _ReportDef(
      "meritBadges",
      "Coach Merit Badges",
      "Monthly coaching-performance badge payouts",
      LucideIcons.award,
      "month",
      (r) => CoachMeritBadgeAutoFinalize(
        child: MeritBadgeEarningsReport(range: r),
      ),
    ),
  ]),
  _Category("Profitability", [
    _ReportDef(
      "profitability",
      "Revenue vs. Payroll",
      "Net profit and margin",
      LucideIcons.scale,
      "month",
      (r) => RevenueVsPayrollReport(range: r),
    ),
  ]),
  _Category("Rewards", [
    _ReportDef(
      "rewards",
      "Rewards & Points",
      "Issued, redeemed, expired, and coach grants",
      LucideIcons.gift,
      "month",
      (r) => RewardsPointsReport(range: r),
    ),
  ]),
];

const _favoritesPrefKey = "onefit:report-favorites";

/// Mirrors ReportsHub.jsx (owner-only) — a catalog of reports grouped by
/// category, each opening full-screen with a shared date-range filter.
/// Search + favorites are ported (favorites persist per-device via
/// SharedPreferences, same "local, not synced across devices" behavior as
/// web's `window.storage`). CSV export is deliberately not ported: web's
/// version is a single shared `<table>` component every report renders
/// through; this port never had that — each report screen already renders
/// its own mobile-card layout independently — so "CSV export, added once"
/// would mean either a ground-up table-widget rewrite across 5 screens, or
/// bolting a differently-shaped exporter onto each one individually. Given
/// this is a coach/owner phone app (reports are for reading in-app, not
/// piping to a spreadsheet on a phone), that cost isn't worth it here.
class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  _ReportDef? _open;
  ReportRange? _range;
  String _query = "";
  Set<String> _favorites = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_favoritesPrefKey);
    if (mounted && saved != null) setState(() => _favorites = saved.toSet());
  }

  Future<void> _toggleFavorite(String key) async {
    setState(() {
      _favorites = {..._favorites};
      _favorites.contains(key) ? _favorites.remove(key) : _favorites.add(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesPrefKey, _favorites.toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_open != null) {
      final range = _range ?? presetRange(_open!.defaultPreset);
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _open = null),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(
                onBack: () => setState(() => _open = null),
                title: _open!.title,
              ),
              const SizedBox(height: 4),
              Text(
                _open!.description,
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              const SizedBox(height: 12),
              DateRangeFilter(
                range: range,
                onChange: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: 14),
              _open!.builder(range),
            ],
          ),
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final filteredCatalog = q.isEmpty
        ? _catalog
        : _catalog
              .map(
                (cat) => _Category(
                  cat.title,
                  cat.reports
                      .where((r) => r.title.toLowerCase().contains(q))
                      .toList(),
                ),
              )
              .where((cat) => cat.reports.isNotEmpty)
              .toList();
    final favReports = [
      for (final cat in filteredCatalog)
        ...cat.reports.where((r) => _favorites.contains(r.key)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppField(
            placeholder: "Search reports…",
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 14),
          if (favReports.isNotEmpty) ...[
            const SectionLabel("Favorites"),
            ...favReports.map(
              (r) => _ReportCard(
                report: r,
                isFavorite: true,
                onToggleFavorite: () => _toggleFavorite(r.key),
                onOpen: () => setState(() {
                  _open = r;
                  _range = null;
                }),
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final cat in filteredCatalog) ...[
            SectionLabel(cat.title),
            ...cat.reports.map(
              (r) => _ReportCard(
                report: r,
                isFavorite: _favorites.contains(r.key),
                onToggleFavorite: () => _toggleFavorite(r.key),
                onOpen: () => setState(() {
                  _open = r;
                  _range = null;
                }),
              ),
            ),
          ],
          if (filteredCatalog.isEmpty)
            const HintBox(text: "No reports match your search."),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onOpen,
  });
  final _ReportDef report;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onOpen,
      child: Row(
        children: [
          Icon(report.icon, size: 18, color: AppColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  report.description,
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onToggleFavorite,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.star,
                size: 17,
                color: isFavorite ? AppColors.gold : AppColors.mute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "widgets.dart";

/// "Sync to Google Calendar" — one button that hands the client's own
/// schedule to whatever calendar they use, and keeps it current on its own.
///
/// Shared by clients (Profile Settings) and coaches (My Profile): the feed
/// scopes itself to whoever the token belongs to, so a client gets the
/// sessions they booked and a coach gets the sessions they're running —
/// nothing here needs to know which is which.
///
/// The link itself is deliberately not shown. Google can be handed a
/// subscription URL directly (calendar.google.com/calendar/r?cid=…), which
/// opens Calendar with an "add this calendar?" prompt already loaded — so
/// there's nothing to copy, paste, or read instructions about. The raw URL is
/// still reachable behind "Set it up manually" for anyone using a calendar
/// app that isn't Google.
class CalendarSyncSection extends ConsumerStatefulWidget {
  const CalendarSyncSection({super.key});

  @override
  ConsumerState<CalendarSyncSection> createState() => _CalendarSyncSectionState();
}

class _CalendarSyncSectionState extends ConsumerState<CalendarSyncSection> {
  String? _url;
  bool _busy = false;
  bool _manual = false;
  String? _error;

  /// Fetched lazily on first use so the common path is a single tap: the
  /// token is minted, then Google is opened, without a preparatory step the
  /// client has to know to press.
  Future<String?> _ensureUrl() async {
    if (_url != null) return _url;
    try {
      final url = await SupabaseService.getCalendarFeedUrl();
      if (mounted) setState(() => _url = url);
      return url;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
      return null;
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final url = await _ensureUrl();
    if (url != null) {
      final target = Uri.parse("https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(url)}");
      try {
        await launchUrl(target, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) setState(() => _error = "Couldn't open Google Calendar — try \"Set it up manually\" below.");
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _showManual() async {
    setState(() => _busy = true);
    await _ensureUrl();
    if (mounted) {
      setState(() {
        _busy = false;
        _manual = true;
      });
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Disconnect this calendar?"),
        content: const Text(
          "Your sessions stop updating in any calendar you've added them to. You can sync again afterwards, but you'll "
          "need to add it back.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Yes, disconnect")),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await SupabaseService.getCalendarFeedUrl(regenerate: true);
      if (mounted) {
        setState(() => _url = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Disconnected. Tap Sync to set it up again.")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.calendar, size: 17, color: AppColors.gold),
              const SizedBox(width: 10),
              const Expanded(
                child: Text("Sync to Google Calendar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Add your sessions to the calendar you already use. New bookings, reschedules and cancellations all follow "
            "automatically.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 12),
          BtnGold(
            full: true,
            onPressed: _busy ? null : _sync,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.calendar, size: 15),
                const SizedBox(width: 8),
                Text(_busy ? "Working…" : "Sync to Calendar"),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          if (!_manual) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : _showManual,
              style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              child: const Text("Set it up manually", style: TextStyle(fontSize: 11)),
            ),
          ],
          if (_manual && _url != null) ...[
            const SizedBox(height: 12),
            const Text("YOUR CALENDAR LINK", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_url!, style: const TextStyle(fontSize: 10.5, color: AppColors.txt, height: 1.4)),
            ),
            const SizedBox(height: 8),
            BtnGhost(
              full: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _url!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copied.")));
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.copy, size: 14),
                  SizedBox(width: 6),
                  Text("Copy link"),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Add it as a calendar subscription in Apple Calendar or Outlook. Treat it like a password — anyone who has "
              "it can see your schedule.",
              style: TextStyle(fontSize: 10.5, color: AppColors.mute, height: 1.4),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy ? null : _regenerate,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              child: const Text("Disconnect calendar", style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

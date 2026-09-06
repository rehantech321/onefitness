import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:share_plus/share_plus.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "widgets.dart";

/// "Sync to Google Calendar" — hands the signed-in person a private calendar
/// feed URL to subscribe to, so their ONE Fitness sessions show up in
/// whatever calendar they already use and stay current on their own.
///
/// Shared by clients (Profile Settings) and coaches (My Profile): the feed
/// scopes itself to whoever the token belongs to, so a client gets the
/// sessions they booked and a coach gets the sessions they're running —
/// nothing here needs to know which is which.
class CalendarSyncSection extends ConsumerStatefulWidget {
  const CalendarSyncSection({super.key});

  @override
  ConsumerState<CalendarSyncSection> createState() => _CalendarSyncSectionState();
}

class _CalendarSyncSectionState extends ConsumerState<CalendarSyncSection> {
  String? _url;
  bool _loading = false;
  bool _revealed = false;
  String? _error;

  Future<void> _load({bool regenerate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await SupabaseService.getCalendarFeedUrl(regenerate: regenerate);
      if (mounted) {
        setState(() {
          _url = url;
          _revealed = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Create a new link?"),
        content: const Text(
          "Your current link stops working immediately. Anyone you've shared it with — including calendars you've already "
          "added it to — will stop receiving your schedule until you add the new one.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Yes, replace it")),
        ],
      ),
    );
    if (confirmed == true) await _load(regenerate: true);
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
            "Add your sessions to the calendar you already use. Once it's set up, new bookings, reschedules and "
            "cancellations all follow automatically — there's nothing to keep in sync by hand.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
          if (!_revealed) ...[
            const SizedBox(height: 10),
            BtnGhost(
              full: true,
              onPressed: _loading ? null : () => _load(),
              child: Text(_loading ? "Getting your link…" : "Get my calendar link"),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          if (_revealed && _url != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _url!,
                style: const TextStyle(fontSize: 10.5, color: AppColors.txt, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: BtnGold(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _url!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Link copied.")),
                        );
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
                ),
                const SizedBox(width: 8),
                BtnGhost(
                  // Getting the link onto a computer is the awkward part of
                  // this flow — Google Calendar can only subscribe to a URL
                  // from its web interface, not the phone app — so sharing it
                  // to email/notes is the practical way across.
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: _url!, subject: "My ONE Fitness schedule"),
                  ),
                  child: const Icon(LucideIcons.share2, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text("HOW TO ADD IT", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 8),
            const _Step(n: "1", text: "On a computer, open calendar.google.com."),
            const _Step(n: "2", text: "In the left sidebar, next to \"Other calendars\", click + and choose \"From URL\"."),
            const _Step(n: "3", text: "Paste the link above and click \"Add calendar\"."),
            const SizedBox(height: 8),
            const Text(
              "Google checks the link for updates on its own schedule — usually every few hours, occasionally up to a day — "
              "so a session you book today may take a little while to appear. The app is always the up-to-the-minute source.",
              style: TextStyle(fontSize: 10.5, color: AppColors.mute, height: 1.4, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            const Text(
              "The same link works in Apple Calendar and Outlook (add it as a calendar subscription). Treat it like a "
              "password — anyone who has it can see your schedule.",
              style: TextStyle(fontSize: 10.5, color: AppColors.mute, height: 1.4),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _loading ? null : _regenerate,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              child: Text(_loading ? "Working…" : "Replace this link", style: const TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.goldDim),
              color: AppColors.gold.withValues(alpha: 0.12),
            ),
            child: Text(n, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.gold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.txt, height: 1.4))),
        ],
      ),
    );
  }
}

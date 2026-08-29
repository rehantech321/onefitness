import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../data/models/roster_client.dart";
import "../../../data/models/squad.dart";
import "../../../data/models/squad_chat_message.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "../log_progress/line_chart_painter.dart";

/// Squad Chat — a group thread scoped to one Squad, entirely separate from
/// the 1:1 client-coach comms log (chat_screen.dart). Members only, no
/// coach; always available regardless of `squad.billingShared`. Reuses the
/// visual language of chat_screen.dart's bubbles/composer/day-separators,
/// adapted for N parties (`isMine` keys off `from == info.id` rather than
/// a fixed 2-party relationship).
class SquadChatTab extends ConsumerStatefulWidget {
  const SquadChatTab({super.key, required this.squad, required this.members});

  final Squad squad;
  final List<RosterClient> members;

  @override
  ConsumerState<SquadChatTab> createState() => _SquadChatTabState();
}

class _SquadChatTabState extends ConsumerState<SquadChatTab> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _pendingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(target);
    }
  }

  String _nameFor(String clientId, String myId, String myName) {
    if (clientId == myId) return myName;
    final matches = widget.members.where((m) => m.id == clientId);
    return matches.isNotEmpty ? matches.first.name : "Member";
  }

  Future<void> _send() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final info = ref.read(clientInfoProvider);
    final entry = SquadChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      from: info.id,
      at: stamp(),
      text: text,
    );
    _msgController.clear();
    setState(() => _pendingIds.add(entry.id));
    final ok = await mutateSquad(ref, widget.squad, (s) => s.copyWith(chat: [entry, ...s.chat]));
    if (mounted) setState(() => _pendingIds.remove(entry.id));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't send — check your connection and try again.")),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final thread = [...widget.squad.chat]..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    return Column(
      children: [
        Expanded(
          child: thread.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "No messages yet — say hi to your Squad.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                    ),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: _buildBubbleList(thread, info.id, info.name),
                ),
        ),
        _SquadComposer(
          controller: _msgController,
          onSend: _send,
        ),
      ],
    );
  }

  List<Widget> _buildBubbleList(List<SquadChatMessage> thread, String myId, String myName) {
    final items = <Widget>[];
    DateTime? lastDay;
    for (final m in thread) {
      final day = DateTime(m.sentAt.year, m.sentAt.month, m.sentAt.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DaySeparator(label: _dayLabel(day)));
        lastDay = day;
      }
      items.add(
        _SquadBubble(
          message: m,
          isMine: m.from == myId,
          senderName: _nameFor(m.from, myId, myName),
          isPending: _pendingIds.contains(m.id),
        ),
      );
    }
    return items;
  }
}

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return "Today";
  if (day == yesterday) return "Yesterday";
  return niceDate(isoDate(day));
}

String _timeOnly(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? "AM" : "PM";
  return "$h:${d.minute.toString().padLeft(2, '0')} $ampm";
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SquadBubble extends StatelessWidget {
  const _SquadBubble({required this.message, required this.isMine, required this.senderName, required this.isPending});
  final SquadChatMessage message;
  final bool isMine;
  final String senderName;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );
    final isShare = message.type == "shared_progress";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 3, bottom: 2),
              child: Text(senderName, style: const TextStyle(fontSize: 10.5, color: AppColors.mute, fontWeight: FontWeight.w600)),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              padding: EdgeInsets.all(isShare ? 10 : 0).add(isShare ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 13, vertical: 9)),
              decoration: BoxDecoration(
                color: isMine ? AppColors.gold : AppColors.card,
                border: isMine ? null : Border.all(color: AppColors.line),
                borderRadius: radius,
              ),
              child: isShare
                  ? _SharedProgressCard(message: message, isMine: isMine)
                  : Text(
                      message.text ?? "",
                      style: TextStyle(color: isMine ? Colors.white : AppColors.txt, fontSize: 14, height: 1.35),
                    ),
            ),
          ),
          const SizedBox(height: 3),
          isPending
              ? const Text("Sending…", style: TextStyle(fontSize: 10.5, color: AppColors.mute, fontStyle: FontStyle.italic))
              : Text(_timeOnly(message.sentAt), style: const TextStyle(fontSize: 10.5, color: AppColors.mute)),
        ],
      ),
    );
  }
}

/// The distinct card content for a `type == "shared_progress"` bubble —
/// swaps in for plain text, everything else about the bubble (alignment,
/// timestamp row, day grouping) stays the same as a normal message.
class _SharedProgressCard extends StatelessWidget {
  const _SharedProgressCard({required this.message, required this.isMine});
  final SquadChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final fg = isMine ? Colors.white : AppColors.txt;
    final muted = isMine ? Colors.white.withValues(alpha: 0.75) : AppColors.mute;
    final payload = message.payload ?? const {};

    switch (message.shareKind) {
      case "photo":
        final img = payload["img"] as String?;
        if (img == null) return const SizedBox.shrink();
        final bytes = base64Decode(img.substring(img.indexOf(",") + 1));
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 190,
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.camera, size: 12, color: muted),
                    const SizedBox(width: 5),
                    Text("Shared a photo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                  ],
                ),
              ),
            ],
          ),
        );

      case "exercises":
        final exercises = (payload["exercises"] as List?)?.whereType<String>().toList() ?? const [];
        final seriesMap = (payload["series"] as Map?) ?? const {};
        // On isMine's gold bubble, a gold line would be invisible against
        // the gold background — swap the first (default) series color for
        // white in that case; the rest of the palette already contrasts.
        final colors = [
          isMine ? Colors.white : AppColors.gold,
          const Color(0xFF64B5F6),
          const Color(0xFFFF7043),
          const Color(0xFFCE93D8),
        ];
        final series = <ChartSeries>[];
        var allVals = <double>[];
        for (var i = 0; i < exercises.length; i++) {
          final vals = ((seriesMap[exercises[i]] as List?) ?? const []).map((v) => (v as num).toDouble()).toList();
          if (vals.isEmpty) continue;
          allVals = [...allVals, ...vals];
          series.add(ChartSeries(values: vals, color: colors[i % colors.length]));
        }
        return _ChartCard(
          icon: LucideIcons.dumbbell,
          label: "Shared lift progress: ${exercises.join(', ')}",
          series: series,
          values: allVals,
          fg: fg,
          muted: muted,
        );

      case "measurements":
        final values = ((payload["values"] as List?) ?? const []).map((v) => (v as num).toDouble()).toList();
        final trend = payload["trend"] as String?;
        final latest = payload["latestValue"];
        final trendArrow = trend == "up" ? "↑" : (trend == "down" ? "↓" : "→");
        return _ChartCard(
          icon: LucideIcons.activity,
          label: "Shared body progress",
          sublabel: latest != null ? "$latest lbs $trendArrow" : null,
          series: [ChartSeries(values: values, color: isMine ? Colors.white : AppColors.gold)],
          values: values,
          fg: fg,
          muted: muted,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.series,
    required this.values,
    required this.fg,
    required this.muted,
  });
  final IconData icon;
  final String label;
  final String? sublabel;
  final List<ChartSeries> series;
  final List<double> values;
  final Color fg;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: muted),
              const SizedBox(width: 5),
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))),
            ],
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sublabel!, style: TextStyle(fontSize: 11, color: muted)),
            ),
          if (values.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 150,
                height: 44,
                child: CustomPaint(
                  painter: LineChartPainter(
                    series: series,
                    minY: values.reduce((a, b) => a < b ? a : b),
                    maxY: values.reduce((a, b) => a > b ? a : b),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SquadComposer extends StatefulWidget {
  const _SquadComposer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  State<_SquadComposer> createState() => _SquadComposerState();
}

class _SquadComposerState extends State<_SquadComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: AppColors.txt, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Message your Squad…",
                    hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.gold)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: hasText ? widget.onSend : null,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasText ? AppColors.gold : AppColors.card,
                  border: hasText ? null : Border.all(color: AppColors.line),
                ),
                child: Icon(LucideIcons.send, size: 17, color: hasText ? Colors.white : AppColors.mute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

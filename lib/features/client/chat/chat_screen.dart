import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";

enum _Channel { email, inapp, both }

const _channelLabels = {_Channel.email: "Email", _Channel.inapp: "In App", _Channel.both: "Both"};

const _prefRecipientKey = "chat_recipient_id";
const _prefChannelKey = "chat_channel";

/// Mirrors Comms.jsx (who: "client") — a timestamped communication log,
/// restyled to read as a real chat: a one-time "who are you messaging"
/// setup (remembered per-device), then a normal message-bubble thread with
/// a slim context bar and a pinned composer. Still a log, not a live
/// socket — every send is a real, timestamped, persisted client_records
/// write, same as before.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  bool _prefsLoaded = false;
  String? _recipientId; // coach id or "business"
  _Channel? _channel;
  final Set<String> _pendingIds = {};

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRecipient = prefs.getString(_prefRecipientKey);
    final savedChannelName = prefs.getString(_prefChannelKey);
    final savedChannel = _Channel.values.where((c) => c.name == savedChannelName);
    if (!mounted) return;
    setState(() {
      _recipientId = savedRecipient;
      _channel = savedChannel.isNotEmpty ? savedChannel.first : null;
      _prefsLoaded = true;
    });
    if (_recipientId != null && _channel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
    }
  }

  Future<void> _confirmSetup(String recipientId, _Channel channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRecipientKey, recipientId);
    await prefs.setString(_prefChannelKey, channel.name);
    if (!mounted) return;
    setState(() {
      _recipientId = recipientId;
      _channel = channel;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

  List<Trainer> _candidateCoaches(ClientInfo info, List<Trainer> trainers, PlatformSettings settings) {
    // "Allow clients to message any coach" off (the default) scopes the
    // picker to coaches the client actually has a relationship with.
    final scoped = settings.clientsCanMessageAnyCoach
        ? trainers
        : trainers.where((t) => t.id == info.primaryTrainerId).toList();
    final real = scoped.isNotEmpty ? scoped : trainers;
    return [...real, Trainer(id: "business", name: settings.businessName)];
  }

  Future<void> _openChangeSheet({
    required List<Trainer> realCandidates,
    required String businessName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _RecipientSetup(
          realCandidates: realCandidates,
          businessName: businessName,
          initialRecipientId: _recipientId,
          initialChannel: _channel,
          confirmLabel: "Save",
          onCancel: () => Navigator.of(ctx).pop(),
          onConfirm: (recipientId, channel) {
            Navigator.of(ctx).pop();
            _confirmSetup(recipientId, channel);
          },
        ),
      ),
    );
  }

  Future<void> _send({
    required Trainer selectedCoach,
    required ClientInfo info,
    required PlatformSettings settings,
    required _Channel channel,
  }) async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final entry = CommMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      who: "client",
      text: text,
      at: stamp(),
      trainerId: selectedCoach.id,
      channel: channel.name,
    );
    _msgController.clear();
    setState(() => _pendingIds.add(entry.id));
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(comms: [entry, ...r.comms]));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      await SupabaseService.updateClientComms(info.id, ref.read(clientRecordProvider).comms);
    } catch (e) {
      ref.read(clientRecordProvider.notifier).update(
            (r) => r.copyWith(comms: r.comms.where((c) => c.id != entry.id).toList()),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send — check your connection and try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingIds.remove(entry.id));
    }
    // "In App" nudges the recipient's phone via a native SMS composer in
    // the source app — a device-integration feature, not a backend one,
    // so it's left as a no-op here; "Email"/"Both" are real.
    if ((channel == _Channel.email || channel == _Channel.both) && selectedCoach.email != null) {
      SupabaseService.sendEmail(
        to: selectedCoach.email!,
        subject: "New message from ${info.name} — ${settings.businessName}",
        text: text,
      ).catchError((Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't send the email — the message is still logged below.")),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) return const SizedBox.shrink();

    final info = ref.watch(clientInfoProvider);
    final client = ref.watch(clientRecordProvider);
    final trainers = ref.watch(trainersProvider);
    final settings = ref.watch(platformSettingsProvider);
    final candidates = _candidateCoaches(info, trainers, settings);
    final realCandidates = candidates.where((t) => t.id != "business").toList();

    final hasSelection = _recipientId != null && _channel != null;

    if (!hasSelection) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _RecipientSetup(
          realCandidates: realCandidates,
          businessName: settings.businessName,
          initialRecipientId: _recipientId,
          initialChannel: _channel,
          confirmLabel: "Start chat",
          onConfirm: _confirmSetup,
        ),
      );
    }

    final selectedCoach = candidates.firstWhere(
      (t) => t.id == _recipientId,
      orElse: () => candidates.first,
    );
    final channel = _channel!;
    final thread = client.comms
        .where((c) => c.trainerId == null || c.trainerId == selectedCoach.id)
        .toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    return Column(
      children: [
        _ContextBar(
          coach: selectedCoach,
          channelLabel: _channelLabels[channel]!,
          onChange: () => _openChangeSheet(realCandidates: realCandidates, businessName: settings.businessName),
        ),
        Expanded(
          child: thread.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "No messages yet — everything you send here is timestamped and logged.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                    ),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: _buildBubbleList(thread),
                ),
        ),
        _Composer(
          controller: _msgController,
          recipientName: selectedCoach.name,
          onSend: () => _send(selectedCoach: selectedCoach, info: info, settings: settings, channel: channel),
        ),
      ],
    );
  }

  List<Widget> _buildBubbleList(List<CommMessage> thread) {
    final items = <Widget>[];
    DateTime? lastDay;
    for (final c in thread) {
      final day = DateTime(c.sentAt.year, c.sentAt.month, c.sentAt.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DaySeparator(label: _dayLabel(day)));
        lastDay = day;
      }
      items.add(_Bubble(message: c, isPending: _pendingIds.contains(c.id)));
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

/// Shown from the ⓘ icon in ClientShell's top bar (chat screen only) —
/// keeps the "record you control" explanation available without a
/// permanent card taking up the top of the thread.
void showChatInfoSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.info, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              const Text(
                "About this chat",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.txt),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(LucideIcons.x, size: 18, color: AppColors.mute),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Every message is logged below, timestamped — a record you control. In App also nudges "
            "the recipient's phone via a text composer. Email actually emails them the message. "
            "Both does both.",
            style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

/// State 1 — "Who are you messaging?", used both as the initial full-screen
/// setup and (pre-filled, with Cancel/Save) as the "Change" bottom sheet.
class _RecipientSetup extends StatefulWidget {
  const _RecipientSetup({
    required this.realCandidates,
    required this.businessName,
    required this.initialRecipientId,
    required this.initialChannel,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  final List<Trainer> realCandidates;
  final String businessName;
  final String? initialRecipientId;
  final _Channel? initialChannel;
  final String confirmLabel;
  final void Function(String recipientId, _Channel channel) onConfirm;
  final VoidCallback? onCancel;

  @override
  State<_RecipientSetup> createState() => _RecipientSetupState();
}

class _RecipientSetupState extends State<_RecipientSetup> {
  late String? _recipientId = widget.initialRecipientId;
  late _Channel? _channel = widget.initialChannel;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _recipientId != null && _channel != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Who are you messaging?",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.txt),
          ),
          const SizedBox(height: 14),
          if (widget.realCandidates.isNotEmpty) ...[
            _coachCard(),
            const SizedBox(height: 10),
          ],
          _businessCard(),
          const SizedBox(height: 20),
          const Text("Send via", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final ch in _Channel.values) ...[
                if (ch != _Channel.email) const SizedBox(width: 8),
                _SegOption(
                  label: _channelLabels[ch]!,
                  selected: _channel == ch,
                  onTap: () => setState(() => _channel = ch),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: canConfirm ? () => widget.onConfirm(_recipientId!, _channel!) : null,
                  child: Text(widget.confirmLabel),
                ),
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(width: 8),
                BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _coachCard() {
    final validId = _recipientId != null && widget.realCandidates.any((t) => t.id == _recipientId);
    final current = validId ? widget.realCandidates.firstWhere((t) => t.id == _recipientId) : widget.realCandidates.first;
    return _SelectableCard(
      selected: validId,
      onTap: () => setState(() => _recipientId = current.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Your coach", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                if (widget.realCandidates.length > 1)
                  InkWell(
                    onTap: () async {
                      final picked = await showModalBottomSheet<Trainer>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: AppColors.card,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        builder: (_) => _CoachSearchSheet(candidates: widget.realCandidates, selectedId: current.id),
                      );
                      if (picked != null) setState(() => _recipientId = picked.id);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.txt),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(LucideIcons.search, size: 15, color: AppColors.mute),
                      ],
                    ),
                  )
                else
                  Text(current.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.txt)),
                const SizedBox(height: 3),
                const Text("Training, form checks, plan questions", style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
              ],
            ),
          ),
          if (validId) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(LucideIcons.checkCircle2, size: 20, color: AppColors.gold)),
        ],
      ),
    );
  }

  Widget _businessCard() {
    final selected = _recipientId == "business";
    return _SelectableCard(
      selected: selected,
      onTap: () => setState(() => _recipientId = "business"),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.businessName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.txt)),
                const SizedBox(height: 3),
                const Text(
                  "Billing, emergencies, or anything that can't wait for your coach",
                  style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
                ),
              ],
            ),
          ),
          if (selected) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(LucideIcons.checkCircle2, size: 20, color: AppColors.gold)),
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

/// Bottom sheet for finding a specific coach by name, discipline, or
/// location — opened from `_coachCard()` whenever there's more than one
/// candidate coach to choose between. Mirrors squad_member_search_screen
/// .dart's search-field-over-a-filtered-list pattern; pops the picked
/// Trainer back to the caller, or null if dismissed without a pick.
class _CoachSearchSheet extends StatefulWidget {
  const _CoachSearchSheet({required this.candidates, required this.selectedId});
  final List<Trainer> candidates;
  final String selectedId;

  @override
  State<_CoachSearchSheet> createState() => _CoachSearchSheetState();
}

class _CoachSearchSheetState extends State<_CoachSearchSheet> {
  final _controller = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? widget.candidates
        : widget.candidates.where((t) {
            final nameMatch = t.name.toLowerCase().contains(q);
            final discMatch = t.disciplines.any((d) => disciplineLabel(d).toLowerCase().contains(q));
            final locMatch = (t.locationName ?? "").toLowerCase().contains(q);
            return nameMatch || discMatch || locMatch;
          }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel("Find a coach"),
                  const SizedBox(height: 8),
                  AppField(
                    controller: _controller,
                    placeholder: "Search by name, discipline, or location…",
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: HintBox(text: "No coaches match your search."),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final t = results[i];
                        final selected = t.id == widget.selectedId;
                        return AppCard(
                          borderColor: selected ? AppColors.gold : null,
                          onTap: () => Navigator.of(context).pop(t),
                          child: Row(
                            children: [
                              Avatar(src: t.photo, name: t.name, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                    if (t.disciplines.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          t.disciplines.map(disciplineLabel).join(", "),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (selected) const Icon(LucideIcons.checkCircle2, size: 18, color: AppColors.gold),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegOption extends StatelessWidget {
  const _SegOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
            border: Border.all(color: selected ? AppColors.gold : AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute),
          ),
        ),
      ),
    );
  }
}

/// State 2's slim sticky header — who this thread is with, how, and a way
/// to change either without leaving the conversation.
class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.coach, required this.channelLabel, required this.onChange});
  final Trainer coach;
  final String channelLabel;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Avatar(src: coach.photo, name: coach.name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coach.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.txt),
                ),
                Text("via $channelLabel", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: Size.zero),
            child: const Text("Change", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isPending});
  final CommMessage message;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final isMine = message.who == "client";
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: isMine ? AppColors.gold : AppColors.card,
                border: isMine ? null : Border.all(color: AppColors.line),
                borderRadius: radius,
              ),
              child: Text(
                message.text,
                style: TextStyle(color: isMine ? Colors.white : AppColors.txt, fontSize: 14, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 3),
          isPending
              ? const Text("Sending…", style: TextStyle(fontSize: 10.5, color: AppColors.mute, fontStyle: FontStyle.italic))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_timeOnly(message.sentAt), style: const TextStyle(fontSize: 10.5, color: AppColors.mute)),
                    if (message.channel != null) ...[
                      const SizedBox(width: 4),
                      _ChannelBadge(channel: message.channel!),
                    ],
                  ],
                ),
        ],
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channel});
  final String channel; // "email" | "inapp" | "both"

  @override
  Widget build(BuildContext context) {
    final icons = switch (channel) {
      "email" => const [LucideIcons.mail],
      "inapp" => const [LucideIcons.phone],
      "both" => const [LucideIcons.mail, LucideIcons.phone],
      _ => const <IconData>[],
    };
    if (icons.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in icons)
          Padding(padding: const EdgeInsets.only(left: 2), child: Icon(i, size: 9, color: AppColors.mute)),
      ],
    );
  }
}

/// Bottom composer, pinned above the tab bar — a single rounded input that
/// grows to 4 lines then scrolls, and a circular send button.
class _Composer extends StatefulWidget {
  const _Composer({required this.controller, required this.recipientName, required this.onSend});
  final TextEditingController controller;
  final String recipientName;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
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
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
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
                    hintText: "Message ${widget.recipientName}…",
                    hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.gold),
                    ),
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

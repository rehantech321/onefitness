import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

enum _Channel { email, inapp, both }

const _channelLabels = {_Channel.email: "Email", _Channel.inapp: "In App", _Channel.both: "Both"};

const _prefRecipientKey = "coach_chat_client_id";
const _prefChannelKey = "coach_chat_channel";

/// Mirrors the client-side chat_screen.dart's redesign, reversed: the coach
/// picks a client (searchable, from their scoped roster) instead of a
/// coach/business, then gets the same message-bubble conversation UI. Same
/// two-state shape: a one-time "who are you messaging" setup (remembered
/// per-device), then a normal chat thread with a slim context bar, a
/// pinned composer, and a "Change" flow to switch clients. Still a
/// timestamped log, not a live socket — every send is a real, persisted
/// client_records write.
class CoachChatScreen extends ConsumerStatefulWidget {
  const CoachChatScreen({super.key});

  @override
  ConsumerState<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends ConsumerState<CoachChatScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  bool _prefsLoaded = false;
  String? _recipientId;
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
      _markThreadRead(_recipientId!);
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
    _markThreadRead(recipientId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Marks a client's unread messages read the moment the coach actually
  /// views that thread — on first opening it and on every "Change" back
  /// into it (including a remembered thread reopened via SharedPreferences)
  /// — mirrors the old _CoachCompose.initState's read-receipt behavior.
  void _markThreadRead(String clientId) {
    final trainerAuth = ref.read(trainerAuthProvider);
    final record = ref.read(trainerClientRecordsProvider)[clientId];
    if (record == null) return;
    bool isUnread(CommMessage m) =>
        m.who == "client" && !m.readByCoach && (m.trainerId == null || m.trainerId == trainerAuth);
    if (!record.comms.any(isUnread)) return;
    final updated = record.comms.map((m) => isUnread(m) ? m.copyWith(readByCoach: true) : m).toList();
    ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(comms: updated));
    SupabaseService.updateClientComms(clientId, updated).catchError((Object _) {});
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

  Future<void> _openChangeSheet(List<ClientInfo> roster) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _RecipientSetup(
          roster: roster,
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
    required ClientInfo client,
    required PlatformSettings settings,
    required _Channel channel,
    required String? trainerAuth,
  }) async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final entry = CommMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      who: "trainer",
      text: text,
      at: stamp(),
      trainerId: trainerAuth,
      readByCoach: true,
      channel: channel.name,
    );
    _msgController.clear();
    setState(() => _pendingIds.add(entry.id));
    ref.read(trainerClientRecordsProvider.notifier).update(client.id, (r) => r.copyWith(comms: [entry, ...r.comms]));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      final comms = ref.read(trainerClientRecordsProvider)[client.id]!.comms;
      await SupabaseService.updateClientComms(client.id, comms);
    } catch (e) {
      ref.read(trainerClientRecordsProvider.notifier).update(
            client.id,
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
    if ((channel == _Channel.email || channel == _Channel.both) && client.email != null) {
      SupabaseService.sendEmail(
        to: client.email!,
        subject: "New message from your coach — ${settings.businessName}",
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

    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    // Platform → Coaches, Access & Security controls this — matches
    // RosterBar's own scoping so Chat and Clients never disagree about
    // which roster a coach can see.
    final coachClientScope = ref.watch(platformSettingsProvider).coachClientScope;
    final roster = ref
        .watch(trainerRosterProvider)
        .where((c) => isOwner || coachClientScope != "own" || c.primaryTrainerId == trainerAuth)
        .toList();
    final records = ref.watch(trainerClientRecordsProvider);
    final settings = ref.watch(platformSettingsProvider);

    final hasSelection = _recipientId != null && _channel != null;
    final selectedMatches = roster.where((c) => c.id == _recipientId);

    if (!hasSelection || selectedMatches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _RecipientSetup(
          roster: roster,
          initialRecipientId: _recipientId,
          initialChannel: _channel,
          confirmLabel: "Start chat",
          onConfirm: _confirmSetup,
        ),
      );
    }

    final client = selectedMatches.first;
    final channel = _channel!;
    final comms = records[client.id]?.comms ?? const <CommMessage>[];
    final thread = comms.where((m) => isOwner || m.trainerId == null || m.trainerId == trainerAuth).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    return Column(
      children: [
        _ContextBar(
          client: client,
          channelLabel: _channelLabels[channel]!,
          onChange: () => _openChangeSheet(roster),
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
          recipientName: client.name,
          onSend: () => _send(client: client, settings: settings, channel: channel, trainerAuth: trainerAuth),
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

/// State 1 — "Who are you messaging?": search the coach's (scoped) roster
/// and pick a client, used both as the initial full-screen setup and
/// (pre-filled, with Cancel/Save) as the "Change" bottom sheet.
class _RecipientSetup extends StatefulWidget {
  const _RecipientSetup({
    required this.roster,
    required this.initialRecipientId,
    required this.initialChannel,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  final List<ClientInfo> roster;
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
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _recipientId != null && _channel != null;
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? widget.roster
        : widget.roster
            .where((c) => c.name.toLowerCase().contains(q) || (c.email ?? "").toLowerCase().contains(q))
            .toList();

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
          AppField(
            controller: _searchController,
            placeholder: "Search clients by name or email…",
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: HintBox(text: "No clients match your search.", bordered: false),
            )
          else
            ...results.map((c) {
              final selected = c.id == _recipientId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _recipientId = c.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.card,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Avatar(src: c.photo, name: c.name, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text(
                                c.email ?? "No email on file",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.mute),
                              ),
                            ],
                          ),
                        ),
                        if (selected) const Icon(LucideIcons.checkCircle2, size: 18, color: AppColors.gold),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 12),
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
  const _ContextBar({required this.client, required this.channelLabel, required this.onChange});
  final ClientInfo client;
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
          Avatar(src: client.photo, name: client.name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
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
    final isMine = message.who == "trainer";
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

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/platform_settings.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/providers/trainer_providers.dart";

enum _Channel { email, inapp, both }

/// Mirrors CoachChat.jsx — the coach-side mirror of the client's Comms
/// screen, reversed: one coach, many per-client threads (an inbox), not a
/// single conversation. The source's "In App" channel nudges the
/// recipient's phone via a native SMS composer — a device-integration
/// feature, not a backend one, so it stays a no-op here; "Email"/"Both"
/// send for real via the send-email Edge Function.
class CoachChatScreen extends ConsumerStatefulWidget {
  const CoachChatScreen({super.key});

  @override
  ConsumerState<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends ConsumerState<CoachChatScreen> {
  String? _selectedId;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final roster = ref.watch(trainerRosterProvider).where((c) => isOwner || c.primaryTrainerId == trainerAuth).toList();
    final records = ref.watch(trainerClientRecordsProvider);

    if (_selectedId != null) {
      final matches = roster.where((c) => c.id == _selectedId);
      if (matches.isEmpty) {
        _selectedId = null;
      } else {
        return _CoachCompose(client: matches.first, onBack: () => setState(() => _selectedId = null));
      }
    }

    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty ? roster : roster.where((c) => c.name.toLowerCase().contains(q) || (c.email ?? "").toLowerCase().contains(q)).toList();

    (ClientInfo, CommMessage?) lastFor(ClientInfo c) {
      final comms = records[c.id]?.comms ?? const <CommMessage>[];
      final relevant = comms.where((m) => m.trainerId == null || isOwner || m.trainerId == trainerAuth).toList();
      return (c, relevant.isEmpty ? null : relevant.first);
    }

    final withMessages = visible.map(lastFor).where((e) => e.$2 != null).toList()..sort((a, b) => b.$2!.at.compareTo(a.$2!.at));
    final withoutMessages = visible.map(lastFor).where((e) => e.$2 == null).toList()..sort((a, b) => a.$1.name.compareTo(b.$1.name));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Chat"),
          AppField(controller: _search, placeholder: "Search clients…", onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          if (withMessages.isNotEmpty) ...[
            const Text("RECENT", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            ...withMessages.map((e) => _ThreadRow(client: e.$1, last: e.$2, onTap: () => setState(() => _selectedId = e.$1.id))),
            const SizedBox(height: 12),
          ],
          const Text("CHOOSE A CLIENT", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          ...withoutMessages.map((e) => _ThreadRow(client: e.$1, last: null, onTap: () => setState(() => _selectedId = e.$1.id))),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.client, required this.last, required this.onTap});
  final ClientInfo client;
  final CommMessage? last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = last != null && last!.who == "client" && !last!.readByCoach;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Avatar(name: client.name, size: 36),
                if (unread) const Positioned(top: -1, right: -1, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFF7FA8C9))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.name, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                if (last != null)
                  Text(
                    "${last!.who == 'trainer' ? 'You: ' : ''}${last!.text}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
              ],
            ),
          ),
          if (last != null) Text(last!.at, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
        ],
      ),
    );
  }
}

class _CoachCompose extends ConsumerStatefulWidget {
  const _CoachCompose({required this.client, required this.onBack});
  final ClientInfo client;
  final VoidCallback onBack;

  @override
  ConsumerState<_CoachCompose> createState() => _CoachComposeState();
}

class _CoachComposeState extends ConsumerState<_CoachCompose> {
  final _controller = TextEditingController();
  _Channel _channel = _Channel.inapp;

  @override
  void initState() {
    super.initState();
    final trainerAuth = ref.read(trainerAuthProvider);
    ref.read(trainerClientRecordsProvider.notifier).update(widget.client.id, (r) => r.copyWith(comms: r.comms.map((m) => m.who == "client" && (m.trainerId == null || m.trainerId == trainerAuth) ? m.copyWith(readByCoach: true) : m).toList()));
    SupabaseService.updateClientComms(widget.client.id, ref.read(trainerClientRecordsProvider)[widget.client.id]!.comms);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final records = ref.watch(trainerClientRecordsProvider);
    final comms = records[widget.client.id]?.comms ?? const <CommMessage>[];
    final thread = comms.where((m) => isOwner || m.trainerId == null || m.trainerId == trainerAuth).toList();

    void send() {
      final text = _controller.text.trim();
      if (text.isEmpty) return;
      final entry = CommMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), who: "trainer", text: text, at: stamp(), trainerId: trainerAuth, readByCoach: true);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.client.id, (r) => r.copyWith(comms: [entry, ...r.comms]));
      SupabaseService.updateClientComms(widget.client.id, ref.read(trainerClientRecordsProvider)[widget.client.id]!.comms).catchError((Object _) {
        ref.read(trainerClientRecordsProvider.notifier).update(widget.client.id, (r) => r.copyWith(comms: r.comms.where((c) => c.id != entry.id).toList()));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send — check your connection and try again.")));
      });
      if ((_channel == _Channel.email || _channel == _Channel.both) && widget.client.email != null) {
        SupabaseService.sendEmail(
          to: widget.client.email!,
          subject: "New message from your coach — $kBusinessName",
          text: text,
        ).catchError((Object e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send the email — the message is still logged below.")));
        });
      }
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Message sent & logged.")));
      setState(() {});
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: widget.client.name),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(color: AppColors.txt, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Type the message you're sending…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 6),
            child: Text("Send via", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
          ),
          Row(
            children: [
              _ChannelButton(label: "Email", selected: _channel == _Channel.email, onTap: () => setState(() => _channel = _Channel.email)),
              const SizedBox(width: 6),
              _ChannelButton(label: "In App", selected: _channel == _Channel.inapp, onTap: () => setState(() => _channel = _Channel.inapp)),
              const SizedBox(width: 6),
              _ChannelButton(label: "Both", selected: _channel == _Channel.both, onTap: () => setState(() => _channel = _Channel.both)),
            ],
          ),
          const SizedBox(height: 10),
          BtnGold(
            full: true,
            onPressed: send,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.send, size: 15), SizedBox(width: 6), Text("Send & log")]),
          ),
          const Padding(padding: EdgeInsets.only(top: 20, bottom: 10), child: SectionLabel("Logged record")),
          if (thread.isEmpty) const HintBox(text: "No messages logged yet."),
          ...thread.map((c) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(c.who == "trainer" ? "YOU" : widget.client.name.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: c.who == "trainer" ? AppColors.gold : const Color(0xFF7FA8C9))),
                        Text(c.at, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(c.text, style: const TextStyle(fontSize: 14, color: AppColors.txt)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ChannelButton extends StatelessWidget {
  const _ChannelButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
            border: Border.all(color: selected ? AppColors.gold : AppColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.gold : AppColors.mute,
            ),
          ),
        ),
      ),
    );
  }
}

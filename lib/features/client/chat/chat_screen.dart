import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/platform_settings.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/comm_message.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";

const _business = Trainer(id: "business", name: kBusinessName);

enum _Channel { email, inapp, both }

/// Mirrors Comms.jsx (who: "client") — a timestamped communication log, not
/// a live chat: compose a message, pick how it also notifies the coach
/// outside the app, send & log, see the full logged thread below.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgController = TextEditingController();
  _Channel _channel = _Channel.inapp;
  String? _selectedCoachId;

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  List<Trainer> _candidateCoaches(ClientInfo info, List<Trainer> trainers) {
    // "Allow clients to message any coach" off (the default) scopes the
    // picker to coaches the client actually has a relationship with.
    final scoped = kClientsCanMessageAnyCoach
        ? trainers
        : trainers.where((t) => t.id == info.primaryTrainerId).toList();
    final real = scoped.isNotEmpty ? scoped : trainers;
    return [...real, _business];
  }

  String _senderLabel(String? trainerId, List<Trainer> trainers) {
    if (trainerId == null || trainerId == "owner") return kBusinessName;
    if (kMessageIdentity == "business") return kBusinessName;
    final match = trainers.where((t) => t.id == trainerId);
    return match.isNotEmpty ? match.first.name : "your coach";
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final client = ref.watch(clientRecordProvider);
    final trainers = ref.watch(trainersProvider);
    final candidates = _candidateCoaches(info, trainers);

    _selectedCoachId ??= candidates.first.id;
    final selectedCoach = candidates.firstWhere(
      (t) => t.id == _selectedCoachId,
      orElse: () => candidates.first,
    );
    final realCandidates = candidates.where((t) => t.id != "business").toList();

    final thread = client.comms
        .where((c) => c.trainerId == null || c.trainerId == selectedCoach.id)
        .toList();

    void send() {
      final text = _msgController.text.trim();
      if (text.isEmpty) return;
      final entry = CommMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        who: "client",
        text: text,
        at: stamp(),
        trainerId: selectedCoach.id,
      );
      ref.read(clientRecordProvider.notifier).update(
            (r) => r.copyWith(comms: [entry, ...r.comms]),
          );
      _msgController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message sent & logged.")),
      );
      setState(() {});
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.07),
              border: Border.all(color: AppColors.goldDim),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "COMMUNICATION LOG",
                  style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Every message is logged below, timestamped — a record you control. In App also nudges "
                  "the recipient's phone via a text composer. Email actually emails them the message. "
                  "Both does both.",
                  style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
                ),
              ],
            ),
          ),

          if (realCandidates.isNotEmpty) ...[
            const Text("Your coach", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: realCandidates.any((t) => t.id == selectedCoach.id) ? selectedCoach.id : realCandidates.first.id,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.txt, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: selectedCoach.id != "business" ? AppColors.gold : AppColors.line),
                ),
              ),
              items: realCandidates
                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCoachId = v),
            ),
            const SizedBox(height: 8),
          ],
          InkWell(
            onTap: () => setState(() => _selectedCoachId = "business"),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: selectedCoach.id == "business" ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
                border: Border.all(color: selectedCoach.id == "business" ? AppColors.gold : AppColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kBusinessName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selectedCoach.id == "business" ? AppColors.gold : AppColors.txt,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Billing, emergencies, or anything that can't wait for your coach",
                    style: TextStyle(fontSize: 11, color: AppColors.mute),
                  ),
                ],
              ),
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.goldDim),
              borderRadius: BorderRadius.circular(8),
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: AppColors.txt),
                children: [
                  const TextSpan(text: "Sending to: "),
                  TextSpan(
                    text: selectedCoach.name,
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),

          SectionLabel("Chat with ${selectedCoach.name}"),
          TextField(
            controller: _msgController,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(color: AppColors.txt, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Type the message you're sending…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.line),
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 6),
            child: Text("Send via", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
          ),
          Row(
            children: [
              _ChannelButton(
                label: "Email",
                selected: _channel == _Channel.email,
                onTap: () => setState(() => _channel = _Channel.email),
              ),
              const SizedBox(width: 6),
              _ChannelButton(
                label: "In App",
                selected: _channel == _Channel.inapp,
                onTap: () => setState(() => _channel = _Channel.inapp),
              ),
              const SizedBox(width: 6),
              _ChannelButton(
                label: "Both",
                selected: _channel == _Channel.both,
                onTap: () => setState(() => _channel = _Channel.both),
              ),
            ],
          ),

          const SizedBox(height: 10),
          BtnGold(
            onPressed: send,
            full: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.send, size: 15),
                SizedBox(width: 6),
                Text("Send & log"),
              ],
            ),
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
                        Text(
                          c.who == "trainer" ? _senderLabel(c.trainerId, trainers).toUpperCase() : "YOU",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: c.who == "trainer" ? AppColors.gold : const Color(0xFF7FA8C9),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.clock, size: 10, color: AppColors.mute),
                            const SizedBox(width: 4),
                            Text(c.at, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
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

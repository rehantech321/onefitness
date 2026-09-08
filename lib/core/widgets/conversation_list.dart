import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "widgets.dart";

/// One row in the recent-conversations list: who it's with, the last thing
/// said, and when.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.name,
    required this.preview,
    required this.at,
    this.photo,
    this.unread = false,
    this.outgoing = false,
  });

  /// The other party's profile id — a client id on the coach side, a coach
  /// id on the client side.
  final String id;
  final String name;
  final String preview;
  final DateTime at;
  final String? photo;
  final bool unread;

  /// Whether the last message was sent by the viewer, which is what earns
  /// the "You: " prefix.
  final bool outgoing;
}

/// Recent conversations, newest first — the screen you land on when opening
/// Chat, and the one you come back to from a thread.
///
/// Deliberately lists only people actually messaged: a roster of hundreds
/// would bury the two conversations that matter. Starting a new one goes
/// through the picker instead, via [onNewChat].
class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.conversations,
    required this.onOpen,
    required this.onNewChat,
    this.newChatLabel = "New message",
    this.emptyText = "No conversations yet.",
  });

  final List<ChatConversation> conversations;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewChat;
  final String newChatLabel;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: conversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: conversations.length,
                  separatorBuilder: (context, i) => const Divider(height: 1, color: AppColors.line, indent: 70),
                  itemBuilder: (context, i) {
                    final c = conversations[i];
                    return InkWell(
                      onTap: () => onOpen(c.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(
                          children: [
                            Avatar(src: c.photo, name: c.name, size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: c.unread ? FontWeight.w800 : FontWeight.w600,
                                            color: AppColors.txt,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _stamp(c.at),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: c.unread ? FontWeight.w700 : FontWeight.w400,
                                          color: c.unread ? AppColors.gold : AppColors.mute,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.outgoing ? "You: ${c.preview}" : c.preview,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.unread ? AppColors.txt : AppColors.mute,
                                            fontWeight: c.unread ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (c.unread) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: BtnGold(
            full: true,
            onPressed: onNewChat,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.penSquare, size: 15),
                const SizedBox(width: 8),
                Text(newChatLabel),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Time for today, weekday within the last week, date beyond that — the
/// convention every messaging app uses, because "14:32" on a message from
/// three weeks ago tells you nothing useful.
String _stamp(DateTime at) {
  final now = DateTime.now();
  final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
  if (sameDay) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return "$h:${at.minute.toString().padLeft(2, "0")} ${at.hour < 12 ? "AM" : "PM"}";
  }
  final diff = now.difference(at).inDays;
  if (diff < 7) {
    const names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return names[at.weekday - 1];
  }
  return "${at.month}/${at.day}/${at.year % 100}";
}

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "widgets.dart";

/// Everyone this user has blocked, with a way to undo it — Apple guideline
/// 1.2 asks for exactly this, and the Terms of Use point people here by
/// name ("Manage blocked users from Settings → Blocked users"), so it has
/// to exist and be reachable under that name.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<({String id, String name})>? _blocked;
  String? _error;

  /// Ids currently being unblocked, so a row can't be tapped twice.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await SupabaseService.loadMyBlocks();
      if (!mounted) return;
      setState(() => _blocked = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blocked = const [];
        _error = "Couldn't load your blocked list — check your connection and try again.";
      });
    }
  }

  Future<void> _unblock(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text("Unblock $name?", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: const Text(
          "You'll see their messages again and you'll both be able to contact each other.",
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.mute),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            child: const Text("Unblock", style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.unblockUser(id);
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        _blocked = _blocked?.where((b) => b.id != id).toList();
      });
      messenger.showSnackBar(SnackBar(content: Text("$name has been unblocked.")));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't unblock just now — check your connection and try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar(onBack: widget.onBack, title: "Blocked users"),
          const SizedBox(height: 14),
          if (blocked == null)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
            )
          else ...[
            if (_error != null) ...[
              HintBox(text: _error!),
              const SizedBox(height: 12),
            ],
            if (blocked.isEmpty)
              const HintBox(
                text: "You haven't blocked anyone. You can block someone from their profile, "
                    "or by holding down one of their messages in Chat.",
              )
            else ...[
              const Text(
                "Blocked people can't message you, and you won't see their messages or find them in search.",
                style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
              ),
              const SizedBox(height: 12),
              for (final b in blocked)
                AppCard(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.ban, size: 18, color: AppColors.errorText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          b.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy.contains(b.id) ? null : () => _unblock(b.id, b.name),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        child: Text(
                          _busy.contains(b.id) ? "Unblocking…" : "Unblock",
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

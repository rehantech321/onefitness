import "package:flutter/widgets.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

/// Neither shell (trainer or client) uses a real `Navigator` — every
/// destination is just a string in `trainerModeProvider`/
/// `clientScreenProvider`. Countless screens *inside* those destinations
/// still have their own local "sub-view" state (an edit form, a detail
/// drilled into, a picking flow) driven by a private `setState`, each with
/// its own working "Back"/"Cancel" closure — but the shell has no way to
/// know one of those is open, so shell-level back/swipe would otherwise
/// jump straight past it.
///
/// This is a tiny app-wide LIFO stack of those local close-closures. Each
/// shell's back handling checks the top of this stack first, before ever
/// touching its own mode history, so back always closes the innermost
/// open thing — one tap, one level — exactly matching how the state is
/// actually nested. A stack (not a single nullable slot) because some
/// destinations nest two levels of local state (e.g. a selected client's
/// own Edit Profile form) — the innermost open scope must win, and when
/// it closes, control must fall back to the next one out, not straight to
/// the shell.
class LocalBackStackNotifier extends Notifier<List<VoidCallback>> {
  @override
  List<VoidCallback> build() => [];

  void push(VoidCallback handler) => state = [...state, handler];

  void pop(VoidCallback handler) => state = [...state]..remove(handler);

  VoidCallback? get top => state.isEmpty ? null : state.last;
}

final localBackStackProvider = NotifierProvider<LocalBackStackNotifier, List<VoidCallback>>(LocalBackStackNotifier.new);

/// Wrap the relevant part of a screen's `build()` with this wherever the
/// screen has local "sub-view" state that isn't its own shell-level mode
/// — pass the same "is a sub-view open" condition and close-closure the
/// screen's own Back/Cancel button already uses. While [isOpen] is true,
/// [onBack] is pushed onto [localBackStackProvider]; it's popped again as
/// soon as [isOpen] goes false, or on dispose (covers navigating away
/// mid-sub-view, e.g. via the drawer, without the local Back button ever
/// having been tapped).
///
/// A screen with several mutually-exclusive local fields (e.g. Booking's
/// `_cancelTarget`/`_denied`/`_picking`) combines them: `isOpen: a != null
/// || b != null || c != null`, `onBack: () => setState(() { a = null; b =
/// null; c = null; })` — the same thing its own Back/Cancel buttons
/// already do, just also reported here.
class LocalBackScope extends ConsumerStatefulWidget {
  const LocalBackScope({super.key, required this.isOpen, required this.onBack, required this.child});

  final bool isOpen;
  final VoidCallback onBack;
  final Widget child;

  @override
  ConsumerState<LocalBackScope> createState() => _LocalBackScopeState();
}

class _LocalBackScopeState extends ConsumerState<LocalBackScope> {
  // A stable handler identity (not `widget.onBack` directly, which is a
  // fresh closure most rebuilds) — always delegates to whatever the
  // latest `widget.onBack` is, so the stack never has to be popped and
  // re-pushed just because the closure reference changed.
  void _handler() => widget.onBack();
  bool _pushed = false;

  /// Held in a field rather than read through `ref` on demand: dispose runs
  /// once the element is already deactivated, and reading a provider through
  /// `ref` at that point throws ("Using \"ref\" when a widget is about to or
  /// has been unmounted is unsafe"). That fired every time a screen was left
  /// with a sub-view still open — the exact case dispose exists to clean up.
  late final LocalBackStackNotifier _stack =
      ref.read(localBackStackProvider.notifier);

  void _sync() {
    if (!mounted) return;
    final stack = _stack;
    if (widget.isOpen && !_pushed) {
      stack.push(_handler);
      _pushed = true;
    } else if (!widget.isOpen && _pushed) {
      stack.pop(_handler);
      _pushed = false;
    }
  }

  /// Always deferred to after the frame. Both entry points below run inside
  /// the build phase, and pushing/popping here writes to a provider the
  /// shells watch — doing that mid-build throws "Tried to modify a provider
  /// while the widget tree was building", which takes the whole screen down
  /// to a blank error box.
  ///
  /// This bit whenever a screen swapped one sub-view for another that is
  /// also a LocalBackScope: Flutter reuses the element, so the swap arrives
  /// as didUpdateWidget with isOpen flipping false -> true, mid-build. The
  /// Access Hub hit it opening a plan's contract, which is how it was found.
  void _syncAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void initState() {
    super.initState();
    _syncAfterFrame();
  }

  @override
  void didUpdateWidget(covariant LocalBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) _syncAfterFrame();
  }

  @override
  void dispose() {
    if (_pushed) {
      _pushed = false;
      _stack.pop(_handler);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

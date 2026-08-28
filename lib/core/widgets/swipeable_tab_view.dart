import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Flutter's default ScrollBehavior only accepts touch/stylus drags — mouse
/// is deliberately excluded so desktop users don't accidentally scroll by
/// clicking a list. That's the right call for a normal scrollable, but this
/// PageView's whole purpose is "swipe to switch tabs" — mouse-drag should
/// work too (Flutter web on desktop, and it's how this got verified).
class _SwipeScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// A tab row wired to a swipeable [PageView] — tapping a tab or swiping the
/// page both keep the two in sync. Shared by Plans (Workout/Nutrition) and
/// Log Progress (Body/Lifts/Photos) so both get the same swipe-between-tabs
/// gesture from one implementation. The owning shell must exclude this
/// screen from its own swipe-to-go-back gesture (see client_shell.dart's
/// `_swipeOwnedByScreen`) or the two horizontal-drag gestures fight.
class SwipeableTabView extends StatefulWidget {
  const SwipeableTabView({
    super.key,
    required this.labels,
    required this.children,
    this.onIndexChanged,
  });

  final List<String> labels;
  final List<Widget> children;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<SwipeableTabView> createState() => _SwipeableTabViewState();
}

class _SwipeableTabViewState extends State<SwipeableTabView> {
  late final PageController _controller = PageController();
  int _index = 0;

  void _goTo(int i) {
    if (i == _index) return;
    _controller.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    widget.onIndexChanged?.call(i);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              for (var i = 0; i < widget.labels.length; i++)
                _TabButton(label: widget.labels[i], selected: _index == i, onTap: () => _goTo(i)),
            ],
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: _SwipeScrollBehavior(),
            child: PageView(
              controller: _controller,
              onPageChanged: _onPageChanged,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2)),
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

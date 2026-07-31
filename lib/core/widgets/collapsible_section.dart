import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `CollapsibleSection` — a tap-to-expand card
/// with a title, optional trailing meta widget, and nested content.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    this.meta,
    this.defaultOpen = false,
    required this.children,
  });

  final String title;
  final Widget? meta;
  final bool defaultOpen;
  final List<Widget> children;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.txt)),
                  ),
                  if (widget.meta != null) widget.meta!,
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
            ),
        ],
      ),
    );
  }
}

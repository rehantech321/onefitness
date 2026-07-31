import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";

/// Mirrors ClientSearchPicker.jsx — a compact name/email search list used
/// inside the scheduling modals.
class ClientSearchPicker extends StatefulWidget {
  const ClientSearchPicker({super.key, required this.roster, required this.onSelect, this.exclude = const []});

  final List<ClientInfo> roster;
  final ValueChanged<ClientInfo> onSelect;
  final List<String> exclude;

  @override
  State<ClientSearchPicker> createState() => _ClientSearchPickerState();
}

class _ClientSearchPickerState extends State<ClientSearchPicker> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _controller.text.trim().toLowerCase();
    final excludeSet = widget.exclude.toSet();
    final visible = widget.roster.where((c) => !excludeSet.contains(c.id)).where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || (c.email ?? "").toLowerCase().contains(q)).take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppField(controller: _controller, placeholder: "Search clients…", onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: visible.isEmpty
              ? const HintBox(text: "No matching clients.")
              : ListView(
                  children: visible
                      .map((c) => AppCard(
                            onTap: () => widget.onSelect(c),
                            child: Row(
                              children: [
                                Avatar(name: c.name, size: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      Text(c.email ?? "", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

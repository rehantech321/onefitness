import "dart:convert";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../../data/models/trainer.dart";

/// Mirrors ImageEditors.jsx's `BeforeAfterEditor`, trimmed per plan: a plain
/// gallery picker per half (no dedicated portrait crop/zoom/rotate step) —
/// add/replace/remove is otherwise fully real. Up to [max] landscape frames,
/// each split into an independent Before (left) / After (right) photo.
/// Default is 6 (product decision — the web source caps at 5).
class BeforeAfterEditor extends StatefulWidget {
  const BeforeAfterEditor({
    super.key,
    required this.value,
    required this.onChange,
    this.max = 6,
  });

  final List<TrainerBeforeAfter> value;
  final ValueChanged<List<TrainerBeforeAfter>> onChange;
  final int max;

  @override
  State<BeforeAfterEditor> createState() => _BeforeAfterEditorState();
}

class _BeforeAfterEditorState extends State<BeforeAfterEditor> {
  final Set<String> _picking = {}; // "$frameId-$side" currently picking

  void _addFrame() {
    if (widget.value.length >= widget.max) return;
    widget.onChange([
      ...widget.value,
      TrainerBeforeAfter(id: "ba-${DateTime.now().microsecondsSinceEpoch}"),
    ]);
  }

  void _removeFrame(String id) =>
      widget.onChange(widget.value.where((f) => f.id != id).toList());

  void _setHalf(String frameId, bool left, String? dataUrl) {
    widget.onChange(
      widget.value
          .map(
            (f) => f.id == frameId
                ? TrainerBeforeAfter(
                    id: f.id,
                    left: left ? dataUrl : f.left,
                    right: left ? f.right : dataUrl,
                  )
                : f,
          )
          .toList(),
    );
  }

  Future<void> _pick(String frameId, bool left) async {
    final key = "$frameId-${left ? 'l' : 'r'}";
    setState(() => _picking.add(key));
    try {
      // Bounded size on pick, same reasoning as pickProfilePhotoDataUrl:
      // an unconstrained phone photo (several MB) base64-encodes into a
      // multi-MB string per half — with up to 6 frames × 2 halves, an
      // unbounded pick here could balloon a single profile save well past
      // what the Supabase REST API accepts in one request, so the save
      // would silently fail. 1600px/82% quality keeps each half a few
      // hundred KB while still looking sharp at this editor's display size.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final ext = picked.path.toLowerCase().endsWith(".png") ? "png" : "jpeg";
        _setHalf(
          frameId,
          left,
          "data:image/$ext;base64,${base64Encode(bytes)}",
        );
      }
    } catch (_) {
      // no-op — same "nothing to surface" precedent as pickProfilePhotoDataUrl
    } finally {
      if (mounted) setState(() => _picking.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...frames.asMap().entries.map((entry) {
          final i = entry.key;
          final frame = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Before & After${frames.length > 1 ? ' ${i + 1}' : ''}",
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mute,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _removeFrame(frame.id),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC97F7F),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(LucideIcons.trash2, size: 13),
                      label: const Text(
                        "Remove",
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                    ),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Row(
                        children: [
                          Expanded(
                            child: _Half(
                              image: frame.left,
                              label: "Before",
                              busy: _picking.contains("${frame.id}-l"),
                              onTap: () => _pick(frame.id, true),
                              onRemove: () => _setHalf(frame.id, true, null),
                            ),
                          ),
                          Container(width: 2, color: AppColors.card),
                          Expanded(
                            child: _Half(
                              image: frame.right,
                              label: "After",
                              busy: _picking.contains("${frame.id}-r"),
                              onTap: () => _pick(frame.id, false),
                              onRemove: () => _setHalf(frame.id, false, null),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (frames.length < widget.max)
          OutlinedButton(
            onPressed: _addFrame,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: const BorderSide(
                color: AppColors.goldDim,
                style: BorderStyle.solid,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.plus, size: 14),
                const SizedBox(width: 6),
                Text(
                  "Add Before & After${frames.isNotEmpty ? ' (${frames.length}/${widget.max})' : ''}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            "Maximum of ${widget.max} Before & After sets.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mute,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({
    required this.image,
    required this.label,
    required this.busy,
    required this.onTap,
    required this.onRemove,
  });

  final String? image;
  final String label;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return InkWell(
        onTap: busy ? null : onTap,
        child: Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                busy ? Icons.hourglass_empty : LucideIcons.imagePlus,
                size: 22,
                color: AppColors.mute,
              ),
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mute,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                busy ? "Opening…" : "Tap to add",
                style: const TextStyle(fontSize: 10, color: AppColors.mute),
              ),
            ],
          ),
        ),
      );
    }
    final bytes = base64Decode(image!.substring(image!.indexOf(",") + 1));
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(bytes, fit: BoxFit.cover),
        Positioned(
          top: 6,
          right: 6,
          child: Row(
            children: [
              _RoundIconButton(
                icon: LucideIcons.pencil,
                onTap: busy ? null : onTap,
              ),
              const SizedBox(width: 5),
              _RoundIconButton(icon: LucideIcons.x, onTap: onRemove),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xB2000000)],
              ),
            ),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x99000000),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }
}

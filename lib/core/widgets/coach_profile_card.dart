import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../utils/domain_labels.dart";
import "../../data/models/trainer.dart";
import "avatar.dart";
import "tag.dart";

/// Mirrors CoachProfileCard.jsx — the read-only "Meet the Coach" view
/// opened from a "Meet the Coach ›" cue in the booking flow: photo,
/// disciplines, locations, bio, and any before/after transformation
/// photos the coach has added.
class CoachProfileCard extends StatelessWidget {
  const CoachProfileCard({super.key, required this.trainer, required this.onClose});

  final Trainer trainer;
  final VoidCallback onClose;

  static Future<void> show(BuildContext context, Trainer trainer) {
    return showDialog(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (ctx) => CoachProfileCard(trainer: trainer, onClose: () => Navigator.of(ctx).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disciplines = trainer.availability.map((b) => b.discipline).toSet().where((d) => d != "programmer").toList();
    final frames = trainer.beforeAfters
        .where((f) => (f.left != null && f.left!.isNotEmpty) || (f.right != null && f.right!.isNotEmpty))
        .toList();
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: screenHeight * 0.06),
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(src: trainer.photo, name: trainer.name, size: 52, active: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trainer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      if (disciplines.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: disciplines.map((d) => Tag(text: disciplineLabel(d))).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(LucideIcons.x, size: 20, color: AppColors.mute),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trainer.locations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.mapPin, size: 12, color: AppColors.goldDim)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              trainer.locations.map((l) => l.name).join(" · "),
                              style: const TextStyle(fontSize: 12, color: AppColors.mute),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (trainer.bio != null && trainer.bio!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(trainer.bio!, style: const TextStyle(fontSize: 14, color: AppColors.txt, height: 1.6)),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 18),
                      child: Text(
                        "This coach hasn't added a bio yet.",
                        style: TextStyle(fontSize: 13, color: AppColors.mute, fontStyle: FontStyle.italic),
                      ),
                    ),
                  if (frames.isNotEmpty) ...[
                    const Text(
                      "CLIENT TRANSFORMATIONS",
                      style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    ...frames.map((f) => _TransformationFrame(frame: f)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransformationFrame extends StatelessWidget {
  const _TransformationFrame({required this.frame});
  final TrainerBeforeAfter frame;

  ImageProvider? _imageFor(String? src) {
    if (src == null || src.isEmpty) return null;
    if (src.startsWith("http")) return NetworkImage(src);
    if (src.startsWith("data:")) return MemoryImage(base64Decode(src.substring(src.indexOf(",") + 1)));
    return FileImage(File(src));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: _TransformationSide(label: "Before", image: _imageFor(frame.left))),
          Container(width: 2, color: AppColors.card),
          Expanded(child: _TransformationSide(label: "After", image: _imageFor(frame.right))),
        ],
      ),
    );
  }
}

class _TransformationSide extends StatelessWidget {
  const _TransformationSide({required this.label, required this.image});
  final String label;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: AppColors.bg,
            child: image != null
                ? Image(image: image!, fit: BoxFit.cover)
                : const Center(child: Text("—", style: TextStyle(color: AppColors.mute, fontSize: 11))),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]),
              ),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../legal/health_sources.dart";
import "../theme/app_colors.dart";

/// Citations for health guidance, with the disclaimer that goes with them.
///
/// App Review guideline 1.4.1 requires that an app showing health or
/// medical recommendations cites its sources, and that "the citations to
/// the sources should be easy for the user to find". So this sits directly
/// under the guidance it supports — expanded by default, not folded away
/// behind a tap, and not moved off to a legal screen.
class SourceCitations extends StatelessWidget {
  const SourceCitations({
    super.key,
    required this.sources,
    required this.disclaimer,
  });

  final List<HealthSource> sources;
  final String disclaimer;

  Future<void> _open(BuildContext context, HealthSource s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
      if (!ok) throw Exception("could not launch");
    } catch (_) {
      // The citation still has to be usable if the browser won't open —
      // showing the address means it can be typed or copied by hand.
      messenger.showSnackBar(
        SnackBar(content: Text(s.url), duration: const Duration(seconds: 8)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.bookOpen, size: 14, color: AppColors.gold),
              SizedBox(width: 7),
              Text(
                "SOURCES",
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.gold,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            disclaimer,
            style: const TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            "This guidance is based on:",
            style: TextStyle(fontSize: 11.5, color: AppColors.txt, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _open(context, s),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.topic,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.mute,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              s.title,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.gold,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 6, top: 2),
                            child: Icon(LucideIcons.externalLink, size: 12, color: AppColors.gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        "${s.publisher} · ${s.year}",
                        style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

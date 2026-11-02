import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:video_player/video_player.dart";

import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";

/// Opens an exercise's demo clip over the current screen.
///
/// A dialog rather than a page: a client reaches for this mid-set, with a
/// barbell at their feet, and wants to glance at the movement and get back to
/// the set grid — not navigate somewhere and find their way home.
Future<void> showExerciseVideo(
  BuildContext context, {
  required String title,
  required String videoPath,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.82),
  builder: (context) => Dialog(
    backgroundColor: AppColors.card,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: AppColors.line),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.mute),
                tooltip: "Close",
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: ExerciseVideoPlayer(
            videoPath: videoPath,
            // The dialog's own height is what a portrait clip would
            // overflow; this leaves room for the title and the scrub bar.
            maxVideoHeight: MediaQuery.of(context).size.height * 0.62,
          ),
        ),
      ],
    ),
  ),
);

/// A tappable bar that opens the clip. Shown only where there is one to play,
/// so its presence is the signal that a demo exists.
class WatchDemoButton extends StatelessWidget {
  const WatchDemoButton({
    super.key,
    required this.title,
    required this.videoPath,
  });

  final String title;
  final String videoPath;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showExerciseVideo(context, title: title, videoPath: videoPath),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.goldDim),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.circlePlay, size: 15, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Watch demo",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 14, color: AppColors.gold),
          ],
        ),
      ),
    );
  }
}

/// Plays one clip from the `exercise-videos` bucket.
///
/// The bucket is public, so playback is a plain progressive HTTPS download —
/// ExoPlayer and AVPlayer both start on the first buffered range rather than
/// waiting for the whole file, which is what makes a 60MB clip watchable on
/// gym wifi.
class ExerciseVideoPlayer extends StatefulWidget {
  const ExerciseVideoPlayer({
    super.key,
    required this.videoPath,
    this.maxVideoHeight,
    this.autoPlay = true,
  });

  final String videoPath;

  /// Whether to start playing as soon as the first frame is ready.
  ///
  /// True where someone asked to watch the clip. False where the player is
  /// just showing what an exercise has — a coach opening an exercise to fix
  /// a typo in its cues should not have a video start talking at them.
  final bool autoPlay;

  /// A ceiling on the video box, for callers whose own height is bounded.
  ///
  /// Coaches film demos holding the phone upright, and a 9:16 clip asked to
  /// fill the width of a dialog wants more height than a short phone has.
  /// AspectRatio honours a bounded height by shrinking the width instead, so
  /// a cap here letterboxes a portrait clip rather than overflowing. Left
  /// null where the player sits in a scroll view, which has no height to
  /// overflow — and where a `Flexible` would instead throw, a flex child
  /// being illegal under unbounded constraints.
  final double? maxVideoHeight;

  @override
  State<ExerciseVideoPlayer> createState() => _ExerciseVideoPlayerState();
}

class _ExerciseVideoPlayerState extends State<ExerciseVideoPlayer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(SupabaseService.exerciseVideoUrl(widget.videoPath)),
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // A technique demo is watched several times over, so it loops rather
      // than stopping dead on the last frame.
      await controller.setLooping(true);
      // And where someone asked to watch it, it starts on its own: one fewer
      // tap with chalk on your hands.
      if (widget.autoPlay) await controller.play();
      setState(() => _controller = controller);
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(
        () => _error = "This video couldn't be played. Check your connection and try again.",
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 16, color: AppColors.mute),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: AppColors.mute),
              ),
            ),
          ],
        ),
      );
    }

    if (controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible so that when this sits in a height-capped box, the video
        // is sized from the space left after the scrub bar rather than from
        // the whole box — otherwise the two together overflow it by the
        // height of the bar.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.maxVideoHeight ?? double.infinity,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              // The clip's own ratio — a coach filming a deadlift holds the
              // phone upright, and forcing that into 16:9 would letterbox
              // the movement down to nothing.
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  // Tap anywhere to pause, so a client can hold the frame at
                  // the bottom of a squat and look at it.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      }),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) => value.isPlaying
                        ? const SizedBox.shrink()
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(LucideIcons.play, size: 26, color: Colors.white),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: VideoProgressColors(
            playedColor: AppColors.gold,
            bufferedColor: AppColors.gold.withValues(alpha: 0.3),
            backgroundColor: AppColors.line,
          ),
        ),
      ],
    );
  }
}

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

import "../../data/models/live_session.dart";

/// The alert tones a coach hears when a client beeps.
///
/// Five options per alert type, picked by the owner in Customize Platform
/// and applied to every coach. The families are deliberately different in
/// rhythm and register rather than just pitch, because they have to be told
/// apart across a gym floor mid-set:
///
///   Help  a two-note rising call, unhurried
///   Spot  fast high pulses — someone is under a loaded bar
///   Done  one short soft note, easy to ignore
class BeepSound {
  const BeepSound({required this.id, required this.name, required this.asset});
  final String id;
  final String name;
  final String asset;
}

const _helpSounds = <BeepSound>[
  BeepSound(id: "help_1", name: "Call", asset: "sounds/help_1.wav"),
  BeepSound(id: "help_2", name: "Rise", asset: "sounds/help_2.wav"),
  BeepSound(id: "help_3", name: "Knock", asset: "sounds/help_3.wav"),
  BeepSound(id: "help_4", name: "Climb", asset: "sounds/help_4.wav"),
  BeepSound(id: "help_5", name: "Bounce", asset: "sounds/help_5.wav"),
];

const _spotSounds = <BeepSound>[
  BeepSound(id: "spot_1", name: "Urgent", asset: "sounds/spot_1.wav"),
  BeepSound(id: "spot_2", name: "Rapid", asset: "sounds/spot_2.wav"),
  BeepSound(id: "spot_3", name: "Alarm", asset: "sounds/spot_3.wav"),
  BeepSound(id: "spot_4", name: "Sharp", asset: "sounds/spot_4.wav"),
  BeepSound(id: "spot_5", name: "Pulse", asset: "sounds/spot_5.wav"),
];

const _doneSounds = <BeepSound>[
  BeepSound(id: "done_1", name: "Tick", asset: "sounds/done_1.wav"),
  BeepSound(id: "done_2", name: "Soft", asset: "sounds/done_2.wav"),
  BeepSound(id: "done_3", name: "Low", asset: "sounds/done_3.wav"),
  BeepSound(id: "done_4", name: "Bright", asset: "sounds/done_4.wav"),
  BeepSound(id: "done_5", name: "Deep", asset: "sounds/done_5.wav"),
];

List<BeepSound> soundsFor(BeepKind kind) => switch (kind) {
      BeepKind.help => _helpSounds,
      BeepKind.spot => _spotSounds,
      BeepKind.done => _doneSounds,
    };

/// The owner's saved choice, or this type's first option when nothing has
/// been chosen or the saved id no longer exists.
BeepSound resolveSound(BeepKind kind, String? savedId) {
  final options = soundsFor(kind);
  for (final s in options) {
    if (s.id == savedId) return s;
  }
  return options.first;
}

String defaultSoundId(BeepKind kind) => soundsFor(kind).first.id;

/// Plays the alert, and buzzes with it.
///
/// Two separate players so a Spot arriving while a Done is still sounding
/// cuts straight through instead of waiting its turn — the whole point of
/// Spot is that it is heard immediately.
class BeepPlayer {
  BeepPlayer._();
  static final BeepPlayer instance = BeepPlayer._();

  final AudioPlayer _alerts = AudioPlayer(playerId: "beep_alerts");
  final AudioPlayer _preview = AudioPlayer(playerId: "beep_preview");
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    try {
      // The coach is holding the phone and looking at it; this must be
      // audible even with the app in front, and must not duck or stop
      // whatever music is playing in the gym.
      await _alerts.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      _configured = true;
    } catch (e) {
      // A device that refuses the audio config should still vibrate and
      // still show the alert — never let this stop the beep arriving.
      debugPrint("BeepPlayer: audio context failed: $e");
    }
  }

  /// The coach's alert: sound plus vibration, as the spec requires.
  Future<void> alert(BeepKind kind, String? soundId) async {
    await _configure();
    final sound = resolveSound(kind, soundId);
    try {
      await _alerts.stop();
      await _alerts.play(AssetSource(sound.asset));
    } catch (e) {
      debugPrint("BeepPlayer: couldn't play ${sound.asset}: $e");
    }
    await buzz(kind);
  }

  /// Vibration is separate from the sound so it still happens on a phone on
  /// silent — which, in a gym, is most of them.
  Future<void> buzz(BeepKind kind) async {
    try {
      switch (kind) {
        case BeepKind.spot:
          // Three sharp knocks: distinguishable in a pocket without looking.
          for (var i = 0; i < 3; i++) {
            await HapticFeedback.heavyImpact();
            await Future<void>.delayed(const Duration(milliseconds: 90));
          }
        case BeepKind.help:
          await HapticFeedback.mediumImpact();
          await Future<void>.delayed(const Duration(milliseconds: 110));
          await HapticFeedback.mediumImpact();
        case BeepKind.done:
          await HapticFeedback.selectionClick();
      }
    } catch (e) {
      debugPrint("BeepPlayer: haptics unavailable: $e");
    }
  }

  /// The owner auditioning a sound in settings. Uses its own player so an
  /// alert arriving mid-preview isn't swallowed.
  Future<void> preview(BeepKind kind, String soundId) async {
    await _configure();
    final sound = resolveSound(kind, soundId);
    try {
      await _preview.stop();
      await _preview.play(AssetSource(sound.asset));
    } catch (e) {
      debugPrint("BeepPlayer: couldn't preview ${sound.asset}: $e");
    }
  }

  Future<void> dispose() async {
    await _alerts.dispose();
    await _preview.dispose();
  }
}

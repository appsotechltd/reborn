import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'listen_audio.dart';

/// The app icon, shown as the lock-screen artwork.
const kListenArtworkAsset = 'assets/audio/artwork.png';

/// Listen mode's lock-screen, notification and headphone controls, on
/// audio_service. Start it once with [AudioServiceListenSession.start].
class AudioServiceListenSession extends BaseAudioHandler
    with SeekHandler
    implements ListenMediaSession {
  AudioServiceListenSession._();

  ListenMediaControls? _controls;
  Uri? _artUri;

  /// Starts the background service. Returns null when it can't start (e.g.
  /// an unsupported platform): Listen mode then plays in the app only.
  static Future<AudioServiceListenSession?> start() async {
    try {
      final session = await AudioService.init(
        builder: AudioServiceListenSession._,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.appsotech.reborn.listen',
          androidNotificationChannelName: 'Listen mode',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: true,
          // Hand Listen mode to the 10 s back button on headphones and the
          // lock screen's seek buttons.
          rewindInterval: Duration(seconds: 10),
          fastForwardInterval: Duration(seconds: 10),
        ),
        // Never hold up the app's start for it.
      ).timeout(const Duration(seconds: 5));
      await session._loadArtwork();
      return session;
    } catch (e) {
      debugPrint('Listen mode: no media session ($e)');
      return null;
    }
  }

  /// Copies the artwork out of the bundle so the system can show it.
  Future<void> _loadArtwork() async {
    try {
      if (kIsWeb) {
        _artUri = Uri.base.resolve('assets/$kListenArtworkAsset');
        return;
      }
      final bytes = await rootBundle.load(kListenArtworkAsset);
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/listen_artwork.png');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      _artUri = file.uri;
    } catch (_) {
      // No artwork.
    }
  }

  @override
  void bind(ListenMediaControls controls) => _controls = controls;

  @override
  void setItem({
    required String id,
    required String title,
    required String subtitle,
    Duration? duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: subtitle,
        album: 'Reborn',
        duration: duration,
        artUri: _artUri,
      ),
    );
  }

  @override
  void setPlayback({
    required bool playing,
    required bool loading,
    required Duration position,
    required double speed,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.rewind,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: loading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  @override
  void clear() {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    mediaItem.add(null);
  }

  // ---- From the lock screen, notification and headphones ----

  @override
  Future<void> play() async => _controls?.play();

  @override
  Future<void> pause() async => _controls?.pause();

  @override
  Future<void> skipToNext() async => _controls?.next();

  @override
  Future<void> skipToPrevious() async => _controls?.previous();

  @override
  Future<void> seek(Duration position) async => _controls?.seek(position);

  @override
  Future<void> stop() async {
    await _controls?.stop();
    await super.stop();
  }
}

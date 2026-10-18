import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads cards aloud. [speakingId] is the id of the card being read, if any.
abstract class Speaker extends ChangeNotifier {
  String? get speakingId;
  Future<void> speak(String id, String text);
  Future<void> stop();

  /// Speeds speech up or down from its normal rate (1.0), e.g. for Listen
  /// mode's speed setting. Takes effect from the next [speak].
  Future<void> setRate(double multiplier) async {}
}

class TtsSpeaker extends Speaker {
  TtsSpeaker() {
    _tts.setCompletionHandler(_done);
    _tts.setCancelHandler(_done);
    _tts.setErrorHandler((_) => _done());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Keep reading with the screen locked (Listen mode's fallback voice).
      _tts.setSharedInstance(true).catchError((_) {});
      _tts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, const [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ])
          .catchError((_) {});
    }
  }

  final FlutterTts _tts = FlutterTts();
  String? _speakingId;
  double _rate = 1;

  /// Bumped by every [speak] and [stop], so a [speak] that is still starting
  /// when it is stopped (or replaced) never reads.
  int _gen = 0;

  @override
  String? get speakingId => _speakingId;

  void _done() {
    _speakingId = null;
    notifyListeners();
  }

  @override
  Future<void> speak(String id, String text) async {
    final gen = ++_gen;
    await _tts.stop();
    if (gen != _gen) return;
    _speakingId = id;
    notifyListeners();
    try {
      await _tts.setSpeechRate((kIsWeb ? 0.95 : 0.48) * _rate);
      if (gen != _gen) return;
      await _tts.speak(text);
    } catch (_) {
      _done();
    }
  }

  @override
  Future<void> stop() async {
    _gen++;
    await _tts.stop();
    _done();
  }

  @override
  Future<void> setRate(double multiplier) async => _rate = multiplier;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}

final speakerProvider = Provider<Speaker>((ref) {
  final s = TtsSpeaker();
  ref.onDispose(s.dispose);
  return s;
});

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads cards aloud. [speakingId] is the id of the card being read, if any.
abstract class Speaker extends ChangeNotifier {
  String? get speakingId;
  Future<void> speak(String id, String text);
  Future<void> stop();
}

class TtsSpeaker extends Speaker {
  TtsSpeaker() {
    _tts.setCompletionHandler(_done);
    _tts.setCancelHandler(_done);
    _tts.setErrorHandler((_) => _done());
  }

  final FlutterTts _tts = FlutterTts();
  String? _speakingId;

  @override
  String? get speakingId => _speakingId;

  void _done() {
    _speakingId = null;
    notifyListeners();
  }

  @override
  Future<void> speak(String id, String text) async {
    await _tts.stop();
    _speakingId = id;
    notifyListeners();
    try {
      await _tts.setSpeechRate(kIsWeb ? 0.95 : 0.48);
      await _tts.speak(text);
    } catch (_) {
      _done();
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _done();
  }

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

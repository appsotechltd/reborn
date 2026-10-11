import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Records a voice message as 16 kHz mono WAV. It streams raw PCM, which
/// works the same on Android, iOS and the web, and adds the WAV header itself.
class VoiceRecorder {
  VoiceRecorder([AudioRecorder? recorder]) : _rec = recorder ?? AudioRecorder();

  final AudioRecorder _rec;
  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;

  static const sampleRate = 16000;

  /// Longest message: the server takes up to 10 MB, about five minutes of WAV.
  static const maxDuration = Duration(minutes: 4);

  /// Starts recording; false when the microphone isn't allowed.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    _pcm.clear();
    final stream = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _sub = stream.listen(_pcm.add);
    return true;
  }

  /// Stops and returns the recording as WAV, or null when nothing was heard.
  Future<Uint8List?> stop() async {
    await _rec.stop();
    await _sub?.cancel();
    _sub = null;
    final pcm = _pcm.takeBytes();
    // Under a quarter of a second is a tap, not a message.
    if (pcm.length < sampleRate ~/ 2) return null;
    return wavFromPcm16(pcm, sampleRate: sampleRate);
  }

  Future<void> cancel() async {
    await _rec.cancel();
    await _sub?.cancel();
    _sub = null;
    _pcm.clear();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _rec.dispose();
  }
}

/// Wraps 16-bit little-endian mono PCM in a WAV header.
Uint8List wavFromPcm16(Uint8List pcm, {required int sampleRate}) {
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // bytes per second
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}

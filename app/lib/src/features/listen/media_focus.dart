import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Only one thing makes sound at a time, anywhere in the app: Listen mode
/// (a card's recording or the device voice), a video with its sound on, an
/// illustrated video's narration, or a Reborn AI reply read aloud.
///
/// Whatever starts making sound calls [claim] with a way to pause it; the
/// one that held the sound before is paused. Listen mode's background music
/// is part of Listen mode, and a feed video playing muted makes no sound, so
/// neither claims.
class MediaFocus {
  Object? _owner;
  void Function()? _pause;

  /// The one making sound now, if any.
  Object? get owner => _owner;

  /// [owner] starts making sound: whatever had it before is paused (and
  /// told through its own [pause]).
  void claim(Object owner, void Function() pause) {
    final before = _pause;
    final was = _owner;
    _owner = owner;
    _pause = pause;
    if (was != null && !identical(was, owner)) before?.call();
  }

  /// [owner] stopped or went away; a no-op if something else has the sound.
  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _pause = null;
  }
}

final mediaFocusProvider = Provider<MediaFocus>((_) => MediaFocus());

import 'package:flutter/widgets.dart';

/// Which explainer video plays in a feed. Only one plays at a time: the one
/// whose card id is [active], and only while the app is in the foreground.
/// Feeds start muted; the reader's sound choice carries to the next video.
///
/// Players under a [VideoAutoplayScope] attach their own context, so a
/// scrolling list can measure how much of each video is on screen.
class VideoAutoplay extends ChangeNotifier {
  String? _active;
  bool _muted = true;
  bool _foreground = true;

  /// The card id that should be playing now, if any.
  String? get playing => _foreground ? _active : null;
  String? get active => _active;
  bool get muted => _muted;

  void setActive(String? id) {
    if (id == _active) return;
    _active = id;
    notifyListeners();
  }

  void setMuted(bool value) {
    if (value == _muted) return;
    _muted = value;
    notifyListeners();
  }

  void toggleMuted() => setMuted(!_muted);

  /// False while the app is in the background: nothing plays.
  void setForeground(bool value) {
    if (value == _foreground) return;
    _foreground = value;
    notifyListeners();
  }

  final players = <String, BuildContext>{};

  /// Called when a player attaches, e.g. to measure visibility again.
  VoidCallback? onAttach;

  void attach(String id, BuildContext context) {
    players[id] = context;
    onAttach?.call();
  }

  void detach(String id, BuildContext context) {
    if (players[id] == context) players.remove(id);
  }
}

/// Gives explainer players below it a [VideoAutoplay]. Without one, a player
/// waits for a tap (the card screen).
class VideoAutoplayScope extends InheritedWidget {
  const VideoAutoplayScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final VideoAutoplay controller;

  static VideoAutoplay? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VideoAutoplayScope>()
      ?.controller;

  @override
  bool updateShouldNotify(VideoAutoplayScope old) =>
      old.controller != controller;
}

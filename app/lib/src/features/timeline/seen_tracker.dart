import 'dart:async';

/// Decides when timeline posts count as seen: once at least half visible for
/// [dwell], batched to [onFlush] (POST /v1/seen) after [batchDelay] or when
/// [maxBatch] ids are waiting. A post that stays half visible for [readDwell]
/// also counts as read, through [onRead] (POST /v1/cards/{id}/view); only
/// reads count toward streaks and the daily goal.
class SeenTracker {
  SeenTracker({
    required this.onFlush,
    this.onRead,
    this.dwell = const Duration(seconds: 1),
    this.readDwell = const Duration(seconds: 8),
    this.batchDelay = const Duration(seconds: 2),
    this.maxBatch = 100,
  });

  final void Function(List<String> ids) onFlush;
  final void Function(String id)? onRead;
  final Duration dwell;
  final Duration readDwell;
  final Duration batchDelay;
  final int maxBatch;

  final _done = <String>{};
  final _timers = <String, Timer>{};
  final _read = <String>{};
  final _readTimers = <String, Timer>{};
  final _pending = <String>[];
  Timer? _flushTimer;

  /// Ids the server already reports as seen.
  void skip(Iterable<String> ids) => _done.addAll(ids);

  bool isSeen(String id) => _done.contains(id);

  /// Reports how much of post [id] is visible, from 0 to 1.
  void update(String id, double visibleFraction) {
    if (onRead != null && !_read.contains(id)) {
      if (visibleFraction >= 0.5) {
        _readTimers.putIfAbsent(
          id,
          () => Timer(readDwell, () => _markRead(id)),
        );
      } else {
        _readTimers.remove(id)?.cancel();
      }
    }
    if (_done.contains(id)) return;
    if (visibleFraction >= 0.5) {
      _timers.putIfAbsent(id, () => Timer(dwell, () => _mark(id)));
    } else {
      _timers.remove(id)?.cancel();
    }
  }

  String? _focused;

  /// The post filling the screen in the swipe feed, or null for none: it
  /// counts as fully visible and the previous one as gone.
  void focus(String? id) {
    if (id == _focused) return;
    final old = _focused;
    _focused = id;
    if (old != null) update(old, 0);
    if (id != null) update(id, 1);
  }

  void _markRead(String id) {
    _readTimers.remove(id);
    if (_read.add(id)) onRead!(id);
  }

  void _mark(String id) {
    _timers.remove(id);
    if (!_done.add(id)) return;
    _pending.add(id);
    if (_pending.length >= maxBatch) {
      flush();
    } else {
      _flushTimer ??= Timer(batchDelay, flush);
    }
  }

  /// Sends whatever is waiting now.
  void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final ids = List<String>.of(_pending);
    _pending.clear();
    onFlush(ids);
  }

  /// Cancels dwell timers and sends what is waiting.
  void dispose() {
    for (final t in [..._timers.values, ..._readTimers.values]) {
      t.cancel();
    }
    _timers.clear();
    _readTimers.clear();
    _focused = null;
    flush();
  }
}

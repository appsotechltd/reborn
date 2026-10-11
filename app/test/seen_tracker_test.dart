import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/timeline/seen_tracker.dart';

void main() {
  // testWidgets runs in a fake-async zone, so timers advance with pump().
  late List<List<String>> batches;
  SeenTracker tracker({int maxBatch = 100}) =>
      SeenTracker(onFlush: batches.add, maxBatch: maxBatch);

  setUp(() => batches = []);

  testWidgets('half visible for a second marks seen, batched', (tester) async {
    final t = tracker();
    t.update('a', 0.6);
    t.update('b', 1);
    await tester.pump(const Duration(milliseconds: 900));
    expect(t.isSeen('a'), isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(t.isSeen('a'), isTrue);
    expect(batches, isEmpty); // waits for the batch delay
    await tester.pump(const Duration(seconds: 2));
    expect(batches, [
      ['a', 'b'],
    ]);
    // Already seen: not sent again.
    t.update('a', 1);
    await tester.pump(const Duration(seconds: 4));
    expect(batches, hasLength(1));
    t.dispose();
  });

  testWidgets('scrolling away before a second cancels', (tester) async {
    final t = tracker();
    t.update('a', 0.5);
    await tester.pump(const Duration(milliseconds: 500));
    t.update('a', 0.4);
    await tester.pump(const Duration(seconds: 4));
    expect(t.isSeen('a'), isFalse);
    expect(batches, isEmpty);
    t.dispose();
  });

  testWidgets('posts the server already saw are skipped', (tester) async {
    final t = tracker()..skip(['a']);
    t.update('a', 1);
    await tester.pump(const Duration(seconds: 4));
    expect(batches, isEmpty);
    t.dispose();
  });

  testWidgets('a full batch flushes at once; dispose flushes the rest', (
    tester,
  ) async {
    final t = tracker(maxBatch: 2);
    for (final id in ['a', 'b', 'c']) {
      t.update(id, 1);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(batches, [
      ['a', 'b'],
    ]);
    t.dispose();
    expect(batches.last, ['c']);
  });

  testWidgets('staying on screen counts as read; scrolling past does not', (
    tester,
  ) async {
    final reads = <String>[];
    final t = SeenTracker(onFlush: batches.add, onRead: reads.add);
    t.update('a', 1);
    t.update('b', 1);
    await tester.pump(const Duration(seconds: 2));
    t.update('b', 0); // scrolled past after being seen
    await tester.pump(const Duration(seconds: 7));
    expect(reads, ['a']);
    expect(t.isSeen('b'), isTrue);
    t.update('a', 1);
    await tester.pump(const Duration(seconds: 9));
    expect(reads, ['a']); // once per post
    t.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/features/listen/listen_audio.dart';
import 'package:reborn/src/features/listen/listen_controller.dart';
import 'package:reborn/src/features/shell/app_shell.dart';
import 'package:reborn/src/features/timeline/timeline_controller.dart';

import 'fake_server.dart';
import 'fakes.dart';
import 'fixtures.dart';
import 'swipe_feed_test.dart' show FakeVideo, phone, swipeUp, video;

Map<String, dynamic> post(String id, {bool withVideo = false}) => postJson(
  cardJsonWith({
    'id': id,
    'title': 'Idea $id',
    'quote': null,
    'audio': {
      'url': '/media/audio/$id.mp3',
      'duration_s': 30,
      'voice': 'bf_emma',
      'voice_name': 'Emma',
    },
    if (withVideo) 'explainer': video(id),
  }),
);

void main() {
  testWidgets('phone: Listen starts from the post on screen, pauses its '
      'video, and docks a mini-player above the tabs', (tester) async {
    final audio = FakeListenAudio();
    final videos = <String, FakeVideo>{};
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [post('p1'), post('p2', withVideo: true), post('p3')],
          'next_cursor': null,
        },
      );
    final container = await pumpApp(
      tester,
      server,
      size: phone,
      overrides: [
        listenAudioProvider.overrideWithValue(audio),
        videoControllerFactoryProvider.overrideWithValue((url) {
          final c = FakeVideo(url);
          videos[url.pathSegments.last.split('.').first] = c;
          return c;
        }),
      ],
    );
    await swipeUp(tester);
    expect(videos['p2']!.value.isPlaying, isTrue);

    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();
    expect(find.text('Now listening'), findsOneWidget);
    expect(container.read(listenProvider).current!.id, 'p2');
    expect(audio.played, [resolveMediaUrl('/media/audio/p2.mp3')]);
    expect(find.text('Read by Emma'), findsOneWidget);

    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();
    // The feed's video waits while Listen mode plays.
    expect(videos['p2']!.value.isPlaying, isFalse);
    final mini = find.byKey(const ValueKey('listen-mini-player'));
    expect(mini, findsOneWidget);
    expect(
      tester.getBottomLeft(mini).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(FloatingNavBar)).dy),
    );

    // Turning the video's sound on is starting it: Listen mode pauses.
    await tester.tap(find.byKey(const ValueKey('video-mute')));
    await tester.pumpAndSettle();
    expect(container.read(listenProvider).playing, isFalse);
    expect(videos['p2']!.value.isPlaying, isTrue);

    // The mini-player follows to another tab.
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(mini, findsOneWidget);
    await container.read(listenProvider.notifier).stop();
    await tester.pumpAndSettle();
    expect(mini, findsNothing);
  });

  testWidgets('wide: Listen starts at the top with the feed topic filter', (
    tester,
  ) async {
    final audio = FakeListenAudio();
    final server = FakeServer()
      ..on('GET /v1/timeline', (c) {
        if (c.query['cursor'] == 'n1') {
          return {
            'posts': [post('p4')],
            'next_cursor': null,
          };
        }
        return {
          'posts': [post('p1'), post('p2'), post('p3')],
          'next_cursor': 'n1',
        };
      })
      ..on(
        'GET /v1/topics',
        (_) => {
          'topics': [
            {'slug': 'money', 'name': 'Money', 'card_count': 3},
          ],
        },
      );
    final container = await pumpApp(
      tester,
      server,
      size: const Size(800, 2000),
      overrides: [listenAudioProvider.overrideWithValue(audio)],
    );
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    final before = server.calls.length;
    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();
    final s = container.read(listenProvider);
    expect(s.current!.id, 'p1');
    // Listen mode asks for further pages with the feed's filter (the
    // queue logic itself is covered in listen_test.dart).
    expect(container.read(timelineProvider.notifier).topics, ['money']);
    expect(s.queue.map((p) => p.id), ['p1', 'p2', 'p3', 'p4']);
    expect(
      server.calls
          .skip(before)
          .where((c) => c.path == '/v1/timeline')
          .every((c) => c.query['topics'] == 'money'),
      isTrue,
    );
    await container.read(listenProvider.notifier).stop();
    await tester.pumpAndSettle();
  });
}

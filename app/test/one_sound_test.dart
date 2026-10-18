import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/features/listen/listen_audio.dart';
import 'package:reborn/src/features/listen/listen_controller.dart';
import 'package:reborn/src/features/listen/media_focus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';
import 'listen_test.dart' show ListenRepo, post, urlOf;
import 'swipe_feed_test.dart' show FakeVideo, video;

/// A device voice that only starts reading a moment after it is asked, as
/// the real one does (it stops whatever it was saying first).
class SlowSpeaker extends FakeSpeaker {
  int stops = 0;

  @override
  Future<void> speak(String id, String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }
}

Future<ProviderContainer> container({
  Speaker? speaker,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(signedInPrefs);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repositoryProvider.overrideWithValue(ListenRepo(prefs)),
      listenAudioProvider.overrideWithValue(FakeListenAudio()),
      speakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('MediaFocus', () {
    test('a new sound pauses the one before it', () {
      final focus = MediaFocus();
      final paused = <String>[];
      focus.claim('a', () => paused.add('a'));
      focus.claim('b', () => paused.add('b'));
      expect(paused, ['a']);
      expect(focus.owner, 'b');
      // Claiming again while it has the sound changes nothing.
      focus.claim('b', () => paused.add('b'));
      expect(paused, ['a']);
    });

    test('release only lets go of its own sound', () {
      final focus = MediaFocus();
      focus.claim('a', () {});
      focus.release('b');
      expect(focus.owner, 'a');
      focus.release('a');
      expect(focus.owner, isNull);
    });
  });

  group('Listen mode', () {
    testWidgets('pauses whatever was playing, and pauses for the next sound', (
      tester,
    ) async {
      final c = await container();
      final focus = c.read(mediaFocusProvider);
      var videoPaused = false;
      focus.claim('video', () => videoPaused = true);

      await c.read(listenProvider.notifier).playCard(post('a').card);
      await tester.pump();
      expect(videoPaused, isTrue);
      expect(c.read(listenProvider).playing, isTrue);
      final audio = c.read(listenAudioProvider) as FakeListenAudio;
      expect(audio.played, [urlOf('a')]);

      focus.claim('another video', () {});
      await tester.pump();
      expect(c.read(listenProvider).playing, isFalse);
      expect(audio.playing, isFalse);
      await c.read(listenProvider.notifier).stop();
    });

    testWidgets('moving on stops the device voice even before it speaks', (
      tester,
    ) async {
      final speaker = SlowSpeaker();
      final c = await container(speaker: speaker);
      final listen = c.read(listenProvider.notifier);
      await listen.startTimeline(posts: [post('a', voiced: false), post('b')]);
      await tester.pump();
      expect(speaker.spoken, hasLength(1));
      // The reader opens another card before the voice got going.
      await listen.follow(ListenTarget.card(post('z').card));
      await tester.pump();
      expect(speaker.stops, 1);
      final audio = c.read(listenAudioProvider) as FakeListenAudio;
      expect(audio.played, [urlOf('z')]);
      await listen.stop();
    });
  });

  group('videos', () {
    Future<(ProviderContainer, Map<String, FakeVideo>)> pumpPlayers(
      WidgetTester tester,
    ) async {
      final videos = <String, FakeVideo>{};
      final c = await container(
        overrides: [
          videoControllerFactoryProvider.overrideWithValue((url) {
            final v = FakeVideo(url);
            videos[url.pathSegments.last.split('.').first] = v;
            return v;
          }),
        ],
      );
      Widget player(String id) => Expanded(
        child: ExplainerPlayer(
          key: ValueKey('player-$id'),
          explainer: Explainer.fromJson({
            ...video(id),
            'width': 1280,
            'height': 720,
          }),
          title: 'Idea $id',
          maxHeight: 300,
        ),
      );
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(body: Column(children: [player('a'), player('b')])),
          ),
        ),
      );
      return (c, videos);
    }

    Finder playOf(String id) => find.descendant(
      of: find.byKey(ValueKey('player-$id')),
      matching: find.byKey(const ValueKey('video-play')),
    );

    testWidgets('starting one video pauses the other', (tester) async {
      final (_, videos) = await pumpPlayers(tester);
      await tester.tap(playOf('a'));
      await tester.pumpAndSettle();
      expect(videos['a']!.value.isPlaying, isTrue);
      await tester.tap(playOf('b'));
      await tester.pumpAndSettle();
      expect(videos['b']!.value.isPlaying, isTrue);
      expect(videos['a']!.value.isPlaying, isFalse);
    });

    testWidgets('a playing video pauses when Listen mode starts', (
      tester,
    ) async {
      final (c, videos) = await pumpPlayers(tester);
      await tester.tap(playOf('a'));
      await tester.pumpAndSettle();
      await c.read(listenProvider.notifier).playCard(post('x').card);
      await tester.pumpAndSettle();
      expect(videos['a']!.value.isPlaying, isFalse);
      // And starting a video pauses Listen mode.
      await tester.tap(playOf('b'));
      await tester.pumpAndSettle();
      expect(videos['b']!.value.isPlaying, isTrue);
      expect(c.read(listenProvider).playing, isFalse);
      await c.read(listenProvider.notifier).stop();
    });

    testWidgets('a card page video pauses when another page opens on top', (
      tester,
    ) async {
      final (_, videos) = await pumpPlayers(tester);
      await tester.tap(playOf('a'));
      await tester.pumpAndSettle();
      expect(videos['a']!.value.isPlaying, isTrue);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Next card')),
        ),
      );
      await tester.pumpAndSettle();
      expect(videos['a']!.value.isPlaying, isFalse);
    });
  });
}

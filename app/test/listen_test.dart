import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/card/card_view.dart';
import 'package:reborn/src/features/listen/listen_audio.dart';
import 'package:reborn/src/features/listen/listen_controller.dart';
import 'package:reborn/src/features/listen/listen_ui.dart';
import 'package:reborn/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';

class ListenRepo extends FakeRepository {
  ListenRepo(super.prefs);

  final pages = <String, PostPage>{};
  final timelineCalls = <(List<String>?, String?)>[];
  final seen = <String>[];
  final views = <String>[];

  @override
  Future<Fetched<PostPage>> timeline({
    List<String>? topics,
    String? cursor,
  }) async {
    timelineCalls.add((topics, cursor));
    return Fetched(pages[cursor] ?? const PostPage(posts: []));
  }

  @override
  Future<void> markSeen(List<String> postIds) async => seen.addAll(postIds);

  @override
  Future<void> recordView(String cardId) async => views.add(cardId);
}

Map<String, dynamic> audioJson(String id) => {
  'url': '/media/audio/$id.mp3',
  'duration_s': 40,
  'voice': 'bm_george',
  'voice_name': 'George',
};

/// A post whose card has a recording, unless [voiced] is false.
Post post(String id, {bool voiced = true}) => samplePost(
  card: {'id': id, 'title': 'Idea $id', 'audio': voiced ? audioJson(id) : null},
);

String urlOf(String id) => resolveMediaUrl('/media/audio/$id.mp3');

class Harness {
  Harness(this.container, this.repo, this.audio, this.speaker, this.prefs);
  final ProviderContainer container;
  final ListenRepo repo;
  final FakeListenAudio audio;
  final FakeSpeaker speaker;
  final SharedPreferences prefs;

  ListenController get listen => container.read(listenProvider.notifier);
  ListenState get state => container.read(listenProvider);
}

Future<Harness> harness({
  bool signedIn = true,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...signedInPrefs,
    ...prefsValues,
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = ListenRepo(prefs);
  final audio = FakeListenAudio();
  final speaker = FakeSpeaker();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repositoryProvider.overrideWithValue(repo),
      listenAudioProvider.overrideWithValue(audio),
      speakerProvider.overrideWithValue(speaker),
    ],
  );
  addTearDown(container.dispose);
  return Harness(container, repo, audio, speaker, prefs);
}

void main() {
  group('CardAudio', () {
    test('parses the audio object and round-trips it', () {
      final card = sampleCard({'audio': audioJson('x--01')});
      final a = card.audio!;
      expect(a.url, '/media/audio/x--01.mp3');
      expect(a.duration, const Duration(seconds: 40));
      expect(a.voice, 'bm_george');
      expect(a.voiceName, 'George');
      expect(IdeaCard.fromJson(card.toJson()).audio!.url, a.url);
      expect(
        resolveMediaUrl(a.url, 'https://api.example.org/'),
        'https://api.example.org/media/audio/x--01.mp3',
      );
    });

    test('absent or empty audio is null', () {
      expect(sampleCard().audio, isNull);
      expect(sampleCard().toJson().containsKey('audio'), isFalse);
      expect(
        sampleCard({
          'audio': {'url': ''},
        }).audio,
        isNull,
      );
    });

    test('the device-voice script matches the recording', () {
      final text = healthCard().spokenText;
      expect(text, contains('Apply it.'));
      expect(text, contains(healthDisclaimer));
      expect(
        sampleCard().spokenText,
        endsWith('From Meditations, by Marcus Aurelius.'),
      );
    });
  });

  group('queue', () {
    testWidgets('plays from the given post and prefetches the next three', (
      tester,
    ) async {
      final h = await harness();
      final posts = [for (var i = 0; i < 6; i++) post('c$i')];
      await h.listen.startTimeline(posts: posts, index: 1);
      await tester.pump();
      expect(h.state.current!.id, 'c1');
      expect(h.state.playing, isTrue);
      expect(h.audio.played, [urlOf('c1')]);
      expect(h.audio.prefetched, [urlOf('c2'), urlOf('c3'), urlOf('c4')]);
      await h.listen.stop();
    });

    testWidgets('advances at the end of a card, with a chime', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.finish();
      await tester.pump();
      expect(h.audio.chimes, 1);
      expect(h.state.current!.id, 'b');
      expect(h.audio.played, [urlOf('a'), urlOf('b')]);
      // The last card ends the stream.
      h.audio.finish();
      await tester.pump();
      expect(h.state.finished, isTrue);
      expect(h.state.playing, isFalse);
      expect(h.audio.chimes, 1);
    });

    testWidgets('previous restarts after 3 s, else goes back a card', (
      tester,
    ) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')], index: 1);
      await tester.pump();
      h.audio.moveTo(const Duration(seconds: 4));
      await tester.pump();
      await h.listen.previous();
      expect(h.state.current!.id, 'b');
      expect(h.audio.seeks.last, Duration.zero);

      h.audio.moveTo(const Duration(seconds: 2));
      await tester.pump();
      await h.listen.previous();
      await tester.pump();
      expect(h.state.current!.id, 'a');
      expect(h.audio.played.last, urlOf('a'));
      // Previous on the first card restarts it.
      await h.listen.previous();
      expect(h.state.current!.id, 'a');
    });

    testWidgets('back 10 s and next', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.moveTo(const Duration(seconds: 25));
      await tester.pump();
      await h.listen.back10();
      expect(h.audio.seeks.last, const Duration(seconds: 15));
      await h.listen.next();
      await tester.pump();
      expect(h.state.current!.id, 'b');
      // Skipping by hand plays no chime.
      expect(h.audio.chimes, 0);
      await h.listen.stop();
    });

    testWidgets('loads the next page when 3 or fewer remain', (tester) async {
      final h = await harness();
      h.repo.pages['p2'] = PostPage(
        posts: [post('c3'), post('c4'), post('c5')],
        nextCursor: null,
      );
      final first = [for (var i = 0; i < 5; i++) post('c$i')];
      await h.listen.startTimeline(
        posts: first,
        cursor: 'p2',
        topics: ['habits'],
      );
      await tester.pump();
      // Four left: no fetch yet.
      expect(h.repo.timelineCalls, isEmpty);
      await h.listen.next();
      await tester.pump();
      expect(h.repo.timelineCalls, hasLength(1));
      expect(h.repo.timelineCalls.single.$1, ['habits']);
      expect(h.repo.timelineCalls.single.$2, 'p2');
      // Already-queued posts aren't added twice.
      expect(h.state.queue.map((p) => p.id), [
        'c0',
        'c1',
        'c2',
        'c3',
        'c4',
        'c5',
      ]);
      await h.listen.stop();
    });

    testWidgets('pause and play resume the recording', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a')]);
      await tester.pump();
      await h.listen.pause();
      expect(h.audio.playing, isFalse);
      expect(h.state.playing, isFalse);
      await h.listen.play();
      expect(h.audio.playing, isTrue);
      // A call pauses it; the end of the call resumes it.
      h.audio.interrupt(resume: false);
      await tester.pump();
      expect(h.state.playing, isFalse);
      h.audio.interrupt(resume: true);
      await tester.pump();
      expect(h.state.playing, isTrue);
      await h.listen.stop();
      expect(h.state.active, isFalse);
    });
  });

  group('seen and read', () {
    testWidgets('skipping within 5 s marks nothing', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.moveTo(const Duration(seconds: 4));
      await tester.pump();
      await h.listen.next();
      expect(h.repo.seen, isEmpty);
      expect(h.repo.views, isEmpty);
      await h.listen.stop();
    });

    testWidgets('skipping after 5 s but before 70% marks seen only', (
      tester,
    ) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.moveTo(const Duration(seconds: 10));
      await tester.pump();
      await h.listen.next();
      expect(h.repo.seen, ['a']);
      expect(h.repo.views, isEmpty);
      await h.listen.stop();
    });

    testWidgets('70% heard marks seen and read once', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.moveTo(const Duration(seconds: 27));
      await tester.pump();
      expect(h.repo.views, isEmpty);
      h.audio.moveTo(const Duration(seconds: 28)); // 70% of 40 s
      await tester.pump();
      expect(h.repo.seen, ['a']);
      expect(h.repo.views, ['a']);
      h.audio.finish();
      await tester.pump();
      expect(h.repo.seen, ['a']);
      expect(h.repo.views, ['a']);
      await h.listen.stop();
    });

    testWidgets('reaching the end marks seen and read', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.finish();
      await tester.pump();
      expect(h.repo.seen, ['a']);
      expect(h.repo.views, ['a']);
      await h.listen.stop();
    });

    testWidgets('signed out, nothing is marked', (tester) async {
      final h = await harness(signedIn: false);
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.audio.finish();
      await tester.pump();
      expect(h.repo.seen, isEmpty);
      expect(h.repo.views, isEmpty);
      await h.listen.stop();
    });
  });

  group('device voice fallback', () {
    testWidgets('cards without audio are read by the device voice', (
      tester,
    ) async {
      final h = await harness();
      final plain = post('a', voiced: false);
      await h.listen.startTimeline(posts: [plain, post('b')]);
      await tester.pump();
      expect(h.audio.played, isEmpty);
      expect(h.speaker.spoken, [plain.card.spokenText]);
      expect(h.state.deviceVoice, isTrue);
      await tester.pump(const Duration(seconds: 3));
      h.speaker.finish();
      await tester.pump();
      expect(h.repo.views, ['a']);
      expect(h.audio.chimes, 1);
      expect(h.audio.played, [urlOf('b')]);
      expect(h.state.deviceVoice, isFalse);
      await h.listen.stop();
    });

    testWidgets('a recording that fails to load is read instead', (
      tester,
    ) async {
      final h = await harness();
      h.audio.failing.add(urlOf('a'));
      final p = post('a');
      await h.listen.startTimeline(posts: [p]);
      await tester.pump();
      expect(h.speaker.spoken, [p.card.spokenText]);
      expect(h.state.deviceVoice, isTrue);
      await h.listen.stop();
    });

    testWidgets('a card the device voice cannot read is skipped', (
      tester,
    ) async {
      final h = await harness();
      await h.listen.startTimeline(
        posts: [post('a', voiced: false), post('b')],
      );
      await tester.pump();
      // Ends at once: no voice available.
      h.speaker.finish();
      await tester.pump();
      expect(h.state.current!.id, 'b');
      expect(h.repo.seen, isEmpty);
      expect(h.audio.played, [urlOf('b')]);
      await h.listen.stop();
    });

    testWidgets('one card from its page: recording first, else the voice', (
      tester,
    ) async {
      final h = await harness();
      await h.listen.playCard(post('a').card);
      await tester.pump();
      expect(h.audio.played, [urlOf('a')]);
      expect(h.state.single, isTrue);
      h.audio.finish();
      await tester.pump();
      expect(h.state.finished, isTrue);
      expect(h.audio.chimes, 0);

      await h.listen.playCard(sampleCard());
      await tester.pump();
      expect(h.speaker.spoken, [sampleCard().spokenText]);
      expect(h.repo.timelineCalls, isEmpty);
      await h.listen.stop();
    });
  });

  group('speed and sleep', () {
    testWidgets('speed applies to the player and is remembered', (
      tester,
    ) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a')]);
      await tester.pump();
      await h.listen.setSpeed(1.25);
      expect(h.audio.speed, 1.25);
      expect(h.prefs.getDouble(ListenController.speedKey), 1.25);
      await h.listen.cycleSpeed();
      expect(h.state.speed, 1.5);
      await h.listen.cycleSpeed();
      expect(h.state.speed, 0.8);
      await h.listen.stop();

      final again = await harness(
        prefsValues: {ListenController.speedKey: 1.25},
      );
      expect(again.state.speed, 1.25);
      await again.listen.startTimeline(posts: [post('a')]);
      await tester.pump();
      expect(again.audio.speed, 1.25);
      await again.listen.stop();
    });

    testWidgets('sleep at the end of this card', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pump();
      h.listen.setSleep(ListenSleep.endOfCard);
      h.audio.finish();
      await tester.pump();
      expect(h.state.playing, isFalse);
      expect(h.state.current!.id, 'b');
      expect(h.audio.played, [urlOf('a')]);
      expect(h.state.sleep, ListenSleep.off);
      await h.listen.play();
      await tester.pump();
      expect(h.audio.played.last, urlOf('b'));
      await h.listen.stop();
    });

    testWidgets('a 15-minute sleep timer pauses', (tester) async {
      final h = await harness();
      await h.listen.startTimeline(posts: [post('a')]);
      await tester.pump();
      h.listen.setSleep(ListenSleep.min15);
      expect(h.state.sleepAt, isNotNull);
      await tester.pump(const Duration(minutes: 14));
      expect(h.state.playing, isTrue);
      await tester.pump(const Duration(minutes: 1));
      expect(h.state.playing, isFalse);
      expect(h.state.sleep, ListenSleep.off);
      await h.listen.stop();
    });
  });

  group('UI', () {
    Future<Harness> pumpPlayer(WidgetTester tester) async {
      final h = await harness();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Text('home'),
              bottomNavigationBar: ListenMiniPlayer(),
            ),
          ),
          GoRoute(
            path: '/listen',
            builder: (_, _) => const NowListeningScreen(),
          ),
          GoRoute(
            path: '/cards/:id',
            builder: (_, s) => Text('card ${s.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp.router(theme: lightTheme, routerConfig: router),
        ),
      );
      return h;
    }

    testWidgets('mini-player shows while listening and opens the player', (
      tester,
    ) async {
      final h = await pumpPlayer(tester);
      expect(find.byKey(const ValueKey('listen-mini-player')), findsNothing);
      await h.listen.startTimeline(posts: [post('a'), post('b')]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listen-mini-player')), findsOneWidget);
      expect(find.text('Idea a'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(h.state.playing, isFalse);
      await tester.tap(find.byTooltip('Next idea'));
      await tester.pump();
      expect(h.state.current!.id, 'b');

      await tester.tap(find.text('Idea b'));
      await tester.pumpAndSettle();
      expect(find.text('Now listening'), findsOneWidget);
      expect(find.byKey(const ValueKey('listen-title')), findsOneWidget);
      expect(find.text('Read by George'), findsOneWidget);
      expect(find.text('Meditations · Marcus Aurelius'), findsOneWidget);
      for (final label in [
        'Back 10 seconds',
        'Previous idea, or start again',
        'Next idea',
        'Sleep timer',
      ]) {
        expect(find.byTooltip(label), findsWidgets, reason: label);
      }
      expect(find.bySemanticsLabel('Play'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('listen-speed')));
      await tester.pump();
      expect(find.text('1.25×'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('listen-sleep')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 minutes').last);
      await tester.pumpAndSettle();
      expect(h.state.sleep, ListenSleep.min30);
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('listen-open-card')));
      await tester.pumpAndSettle();
      expect(find.text('card b'), findsOneWidget);
      await h.listen.stop();
      await tester.pumpAndSettle();
    });

    testWidgets('the card page Listen button prefers the recording', (
      tester,
    ) async {
      final h = await harness();
      final card = post('a').card;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            theme: lightTheme,
            home: Scaffold(
              body: SingleChildScrollView(child: IdeaCardView(card: card)),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Listen'));
      await tester.pump();
      expect(h.audio.played, [urlOf('a')]);
      expect(h.speaker.spoken, isEmpty);
      expect(find.text('Stop'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(h.state.active, isFalse);
      expect(find.text('Listen'), findsOneWidget);
    });
  });
}

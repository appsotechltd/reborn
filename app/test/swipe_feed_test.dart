import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/features/post/post_view.dart';
import 'package:video_player/video_player.dart';

import 'fake_server.dart';
import 'fixtures.dart';

/// A phone: below the swipe-feed breakpoint.
const phone = Size(400, 1400);

Map<String, dynamic> post(
  String id, {
  bool? seen,
  Map<String, dynamic>? explainer,
  String? body,
  Map<String, dynamic>? postImage,
}) => postJson(
  cardJsonWith({
    'id': id,
    'title': 'Idea $id',
    'quote': null,
    'explainer': ?explainer,
    'body': ?body,
    'post_image': ?postImage,
  }),
  viewer: seen == null
      ? null
      : {'reaction': null, 'favorited': false, 'seen': seen},
);

Map<String, dynamic> video(String id) => {
  'kind': 'animated',
  'video_url': '/media/$id.mp4',
  'poster_url': '/media/$id.jpg',
  'duration_s': 42,
  'width': 720,
  'height': 1280,
};

Map<String, dynamic> picture(String id, {String alt = ''}) => {
  'url': '/media/images/posts/v1/$id.jpg',
  'width': 1080,
  'height': 1350,
  'alt': alt,
};

Map<String, dynamic> page(List<Map<String, dynamic>> posts, [String? next]) => {
  'posts': posts,
  'next_cursor': next,
};

/// A video controller that plays instantly, with no platform behind it.
class FakeVideo extends VideoPlayerController {
  FakeVideo(super.url) : super.networkUrl();

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 42),
      size: const Size(720, 1280),
    );
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);

  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);

  @override
  Future<Duration?> get position async => Duration.zero;

  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

/// Fake controllers by video id (the URL's file name without extension).
class Videos {
  final byId = <String, FakeVideo>{};
  late final override = videoControllerFactoryProvider.overrideWithValue((url) {
    final c = FakeVideo(url);
    byId[url.pathSegments.last.split('.').first] = c;
    return c;
  });
}

Finder get feed => find.byKey(const ValueKey('swipe-feed'));

Future<void> swipeUp(WidgetTester tester) async {
  await tester.fling(feed, const Offset(0, -300), 1500);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a swipe moves exactly one post, keys too', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([for (var i = 1; i <= 6; i++) post('p$i')]),
      );
    await pumpApp(tester, server, size: phone);
    expect(feed, findsOneWidget);
    expect(find.text('Idea p1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Post 1 of 6')), findsOneWidget);

    await swipeUp(tester);
    expect(find.text('Idea p1'), findsNothing);
    expect(find.text('Idea p2'), findsOneWidget);
    expect(find.text('Idea p3'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Post 2 of 6')), findsOneWidget);

    // Even a hard fling moves one post.
    await tester.fling(feed, const Offset(0, -900), 4000);
    await tester.pumpAndSettle();
    expect(find.text('Idea p3'), findsOneWidget);
    expect(find.text('Idea p4'), findsNothing);

    // Back down one.
    await tester.fling(feed, const Offset(0, 300), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Idea p2'), findsOneWidget);

    // Arrow keys on web and desktop.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Idea p3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Idea p2'), findsOneWidget);
  });

  testWidgets('a long post is cut to fit its page, with Read more', (
    tester,
  ) async {
    final long = List.filled(30, 'A long paragraph of the idea.').join('\n\n');
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('p1'), post('p2', body: long), post('p3')]),
      );
    await pumpApp(tester, server, size: phone);
    await swipeUp(tester);
    expect(find.text('Idea p2'), findsOneWidget);
    final p2 = find.byKey(const ValueKey('page-p2'));

    // Nothing scrolls inside the page: the body is cut to whole lines.
    expect(
      find.descendant(of: p2, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final body = tester.widget<Text>(
      find.descendant(
        of: p2,
        matching: find.byKey(const ValueKey('preview-body')),
      ),
    );
    expect(body.maxLines, lessThan(59)); // 30 paragraphs and the gaps
    expect(body.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull); // no overflow

    // Read more, named for the post, above the pinned action bar.
    final readMore = find.descendant(
      of: p2,
      matching: find.byKey(const ValueKey('read-more')),
    );
    expect(readMore, findsOneWidget);
    expect(find.bySemanticsLabel('Read more: Idea p2'), findsOneWidget);
    final favourite = find.descendant(
      of: p2,
      matching: find.byKey(const ValueKey('post-favorite')),
    );
    expect(
      tester.getRect(readMore).bottom,
      lessThanOrEqualTo(tester.getRect(favourite).top),
    );
    expect(tester.getRect(favourite).bottom, lessThanOrEqualTo(phone.height));

    // One swipe moves one post, not through the long body.
    await swipeUp(tester);
    expect(find.text('Idea p3'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Post 3 of 3')), findsOneWidget);
  });

  testWidgets('Read more opens the full card and records a read', (
    tester,
  ) async {
    final long = List.filled(30, 'A long paragraph of the idea.').join('\n\n');
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([
          post('p1', seen: false, body: long),
          post('p2', seen: false),
          post('p3', seen: false),
        ]),
      )
      ..on('POST /v1/seen', (_) => const Reply.empty())
      ..on('GET /v1/posts/p1', (_) => post('p1', body: long))
      ..on('POST /v1/cards/p1/view', (_) => const Reply.empty());
    await pumpApp(tester, server, prefs: signedInPrefs, size: phone);
    expect(find.text('APPLY IT'), findsNothing); // not in the preview

    await tester.tap(find.byKey(const ValueKey('read-more')));
    await tester.pumpAndSettle();
    expect(find.text('Idea'), findsOneWidget); // the card screen's title
    expect(find.text('APPLY IT'), findsOneWidget);
    expect(server.called('POST /v1/cards/p1/view'), hasLength(1));

    // Back on the feed, on the same post, and a swipe still moves one.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Idea p1'), findsOneWidget);
    await swipeUp(tester);
    expect(find.text('Idea p2'), findsOneWidget);
    expect(find.text('Idea p3'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Post 2 of 3')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // let the seen call land
  });

  testWidgets('an image post shows its picture to fit, and opens the card', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([
          post('p1', postImage: picture('p1', alt: 'A lamp on a desk')),
          post('p2', postImage: picture('p2')),
        ]),
      )
      ..on(
        'GET /v1/posts/p1',
        (_) => post('p1', postImage: picture('p1', alt: 'A lamp on a desk')),
      )
      ..on('POST /v1/cards/p1/view', (_) => const Reply.empty());
    await pumpApp(tester, server, size: phone);
    final p1 = find.byKey(const ValueKey('page-p1'));
    final image = find.descendant(
      of: p1,
      matching: find.byKey(const ValueKey('post-image')),
    );
    expect(image, findsOneWidget);
    expect(find.bySemanticsLabel('A lamp on a desk'), findsOneWidget);
    // The title is in the picture: no text preview.
    expect(find.text('Idea p1'), findsNothing);
    expect(find.byKey(const ValueKey('preview-body')), findsNothing);
    expect(tester.takeException(), isNull);

    // At its own 4:5 shape, above Read the idea, Listen and the action bar.
    final rect = tester.getRect(image);
    expect(rect.height / rect.width, closeTo(1.25, 0.01));
    final readMore = find.descendant(
      of: p1,
      matching: find.byKey(const ValueKey('read-more')),
    );
    expect(readMore, findsOneWidget);
    expect(find.bySemanticsLabel('Read more: Idea p1'), findsOneWidget);
    final listen = find.descendant(
      of: p1,
      matching: find.byKey(const ValueKey('post-listen')),
    );
    expect(listen, findsOneWidget);
    final favourite = find.descendant(
      of: p1,
      matching: find.byKey(const ValueKey('post-favorite')),
    );
    expect(rect.bottom, lessThanOrEqualTo(tester.getRect(readMore).top));
    expect(
      tester.getRect(readMore).bottom,
      lessThanOrEqualTo(tester.getRect(favourite).top),
    );
    expect(tester.getRect(favourite).bottom, lessThanOrEqualTo(phone.height));

    // Without alt text the picture is named for the card.
    await swipeUp(tester);
    expect(find.bySemanticsLabel('Idea p2'), findsOneWidget);

    // Tapping the picture opens the full card, which is unchanged.
    await tester.fling(feed, const Offset(0, 300), 1500);
    await tester.pumpAndSettle();
    await tester.tap(image);
    await tester.pumpAndSettle();
    expect(find.text('APPLY IT'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-image')), findsNothing);
  });

  test('a video post plays its video, not its picture', () {
    final withPicture = cardJsonWith({'post_image': picture('x')});
    expect(feedPostImage(sampleCard(withPicture)), isNotNull);
    expect(
      feedPostImage(sampleCard({...withPicture, 'explainer': video('x')})),
      isNull,
    );
  });

  testWidgets('preloads near the end and keeps going into older posts', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/timeline', (c) {
        if (c.query['cursor'] == 'n1') {
          return page([post('s1', seen: true), post('s2', seen: true)]);
        }
        return page([
          for (var i = 1; i <= 5; i++) post('p$i', seen: false),
        ], 'n1');
      })
      ..on('POST /v1/seen', (_) => const Reply.empty())
      ..on('POST /v1/cards/p1/view', (_) => const Reply.empty());
    await pumpApp(tester, server, prefs: signedInPrefs, size: phone);
    List<String?> cursors() => server
        .called('GET /v1/timeline')
        .map((c) => c.query['cursor'])
        .toList();
    expect(cursors(), [null]); // four posts still ahead

    await swipeUp(tester); // p2: three left
    expect(cursors(), [null, 'n1']);
    expect(find.bySemanticsLabel(RegExp(r'^Post 2 of 7$')), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await swipeUp(tester);
    }
    // Past the unseen posts: the caught-up line, then older ones.
    expect(find.text('Idea s1'), findsOneWidget);
    expect(find.text("You're all caught up"), findsOneWidget);
    await swipeUp(tester);
    expect(find.text('Idea s2'), findsOneWidget);
    await swipeUp(tester);
    expect(find.text("That's everything for now."), findsOneWidget);
    expect(cursors(), [null, 'n1']);
  });

  testWidgets('a failed page shows Try again inline, and retry continues', (
    tester,
  ) async {
    var fail = true;
    final server = FakeServer()
      ..on('GET /v1/timeline', (c) {
        if (c.query['cursor'] == 'n1') {
          return fail
              ? Reply.error(500, 'internal', 'Something broke')
              : page([post('p3')]);
        }
        return page([post('p1'), post('p2')], 'n1');
      });
    await pumpApp(tester, server, size: phone);
    await swipeUp(tester);
    await swipeUp(tester);
    expect(find.text("Couldn't load more ideas."), findsOneWidget);
    expect(find.text('Something broke'), findsOneWidget);
    // It waits for the reader instead of retrying on its own.
    await tester.pump(const Duration(seconds: 5));
    expect(server.called('GET /v1/timeline'), hasLength(2));

    fail = false;
    await tester.tap(find.byKey(const ValueKey('load-more-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Idea p3'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Post 3 of 3$')), findsOneWidget);
  });

  testWidgets('the current video plays muted, others pause, tap for sound', (
    tester,
  ) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([
          post('v1', explainer: video('v1')),
          post('v2', explainer: video('v2')),
          post('p3'),
        ]),
      );
    await pumpApp(tester, server, size: phone, overrides: [videos.override]);
    final v1 = videos.byId['v1']!;
    expect(v1.value.isPlaying, isTrue);
    expect(v1.value.volume, 0);
    expect(v1.value.isLooping, isTrue);
    expect(videos.byId['v2'], isNull); // not on screen, not streaming

    // Sound on with the small button, off again by tapping the film.
    final mute = find.byKey(const ValueKey('video-mute'));
    expect(find.byTooltip('Turn sound on'), findsOneWidget);
    await tester.tap(mute);
    await tester.pump();
    expect(v1.value.volume, 1);
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-surface')));
    await tester.pump();
    expect(v1.value.volume, 0);
    await tester.tap(mute);
    await tester.pump();

    // The next video takes over, with the reader's sound choice.
    await swipeUp(tester);
    final v2 = videos.byId['v2']!;
    expect(v2.value.isPlaying, isTrue);
    expect(v2.value.volume, 1);
    expect(v1.disposed || !v1.value.isPlaying, isTrue);

    // Backgrounding the app pauses it; coming back resumes.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(v2.value.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(v2.value.isPlaying, isTrue);

    // A post without a video: nothing plays.
    await swipeUp(tester);
    expect(v2.disposed || !v2.value.isPlaying, isTrue);
  });

  testWidgets('wide screens keep the column, playing one visible video', (
    tester,
  ) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([
          post('v1', explainer: video('v1')),
          post('v2', explainer: video('v2')),
        ]),
      );
    await pumpApp(
      tester,
      server,
      size: const Size(1000, 1300),
      overrides: [videos.override],
    );
    expect(feed, findsNothing);
    expect(videos.byId.keys, containsAll(['v1']));
    final playing = videos.byId.entries.where((e) => e.value.value.isPlaying);
    expect(playing.map((e) => e.key), ['v1']); // the top one
    expect(playing.single.value.value.volume, 0);

    // Scroll the second into view: it takes over and the first pauses.
    final first = find.byKey(const ValueKey('timeline-v1'));
    await tester.drag(first, Offset(0, -tester.getRect(first).bottom + 100));
    await tester.pumpAndSettle();
    expect(videos.byId['v2']!.value.isPlaying, isTrue);
    expect(videos.byId['v1']!.value.isPlaying, isFalse);
  });

  Map<String, dynamic> withWide(String id) => {
    ...video(id),
    'landscape': {
      'video_url': '/media/$id-wide.mp4',
      'poster_url': '/media/$id-wide.jpg',
      'width': 1280,
      'height': 720,
    },
  };

  testWidgets('cards play the landscape cut on phones and wide screens', (
    tester,
  ) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('v1', explainer: withWide('v1'))]),
      );
    await pumpApp(
      tester,
      server,
      size: const Size(1000, 1300),
      overrides: [videos.override],
    );
    expect(videos.byId.keys, ['v1-wide']);
    expect(videos.byId['v1-wide']!.value.isPlaying, isTrue);

    final phoneVideos = Videos();
    await pumpApp(
      tester,
      server,
      size: phone,
      overrides: [phoneVideos.override],
    );
    expect(phoneVideos.byId.keys, ['v1-wide']);
  });

  testWidgets('full screen on an upright phone plays the portrait cut from '
      'the same moment, then the card carries on in landscape', (tester) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('v1', explainer: withWide('v1'))]),
      );
    await pumpApp(tester, server, size: phone, overrides: [videos.override]);
    final wide = videos.byId['v1-wide']!;
    await wide.seekTo(const Duration(seconds: 7));

    await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-fullscreen-page')), findsOneWidget);
    final tall = videos.byId['v1']!;
    expect(tall.value.isPlaying, isTrue);
    expect(tall.value.volume, 1);
    expect(tall.value.position, const Duration(seconds: 7));
    expect(wide.value.isPlaying, isFalse);

    await tall.seekTo(const Duration(seconds: 12));
    await tester.tap(find.byKey(const ValueKey('video-exit-fullscreen')));
    await tester.pumpAndSettle();
    expect(tall.disposed, isTrue);
    expect(wide.value.position, const Duration(seconds: 12));
    expect(wide.value.isPlaying, isTrue);
    expect(wide.value.volume, 0);
  });

  testWidgets('full screen on a wide screen keeps the landscape cut', (
    tester,
  ) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('v1', explainer: withWide('v1'))]),
      );
    await pumpApp(
      tester,
      server,
      size: const Size(1000, 1300),
      overrides: [videos.override],
    );
    await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
    await tester.pumpAndSettle();
    expect(videos.byId.keys, ['v1-wide']);
    expect(videos.byId['v1-wide']!.value.volume, 1);
  });

  testWidgets('sharing a video post offers the link, the tall and the wide '
      'video', (tester) async {
    final videos = Videos();
    final sharer = FakeSharer();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('v1', explainer: withWide('v1'))]),
      )
      ..on('POST /v1/posts/v1/share', (_) => const Reply.empty());
    await pumpApp(
      tester,
      server,
      size: phone,
      sharer: sharer,
      overrides: [videos.override],
    );
    await tester.tap(find.byKey(const ValueKey('post-share')).first);
    await tester.pumpAndSettle();
    expect(find.text('Status, Reels, Shorts, TikTok'), findsOneWidget);
    expect(find.text('YouTube, Facebook, X, LinkedIn'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-video-wide')));
    await tester.pumpAndSettle();
    expect(sharer.files.single.path, '/media/v1-wide.mp4');
    expect(server.called('POST /v1/posts/v1/share').single.body, {
      'channel': 'native',
    });

    await tester.tap(find.byKey(const ValueKey('post-share')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-video-tall')));
    await tester.pumpAndSettle();
    expect(sharer.files.last.path, '/media/v1.mp4');

    await tester.tap(find.byKey(const ValueKey('post-share')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-link')));
    await tester.pumpAndSettle();
    expect(sharer.shared.last, contains('/ideas/v1'));
    expect(sharer.files, hasLength(2));
  });

  testWidgets('sharing a post with a picture puts the picture in the share '
      'with its link, with no extra choice', (tester) async {
    final sharer = FakeSharer();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([
          post(
            'p1',
            postImage: {'url': '/media/p1.jpg', 'width': 1080, 'height': 1350},
          ),
        ]),
      )
      ..on('POST /v1/posts/p1/share', (_) => const Reply.empty());
    await pumpApp(tester, server, size: phone, sharer: sharer);
    await tester.tap(find.byKey(const ValueKey('post-share')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-link')), findsNothing);
    expect(sharer.files.single.path, '/media/p1.jpg');
    expect(sharer.fileNames.single, 'reborn-p1.jpg');
    expect(sharer.shared.single, contains('/ideas/p1'));
    expect(server.called('POST /v1/posts/p1/share').single.body, {
      'channel': 'native',
    });
  });

  testWidgets('the current post counts as read after 8 seconds', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('p1', seen: false), post('p2', seen: false)]),
      )
      ..on('POST /v1/seen', (_) => const Reply.empty())
      ..on('POST /v1/cards/p1/view', (_) => const Reply.empty())
      ..on('POST /v1/cards/p2/view', (_) => const Reply.empty());
    await pumpApp(tester, server, prefs: signedInPrefs, size: phone);

    // p1 is seen after a second, but leaving before 8s means not read.
    await tester.pump(const Duration(seconds: 3));
    expect(server.called('POST /v1/seen').single.body['post_ids'], ['p1']);
    await swipeUp(tester);
    await tester.pump(const Duration(seconds: 7));
    expect(server.log, isNot(contains('POST /v1/cards/p1/view')));
    expect(server.log, isNot(contains('POST /v1/cards/p2/view')));

    await tester.pump(const Duration(seconds: 2));
    expect(server.called('POST /v1/cards/p2/view'), hasLength(1));
    expect(server.log, isNot(contains('POST /v1/cards/p1/view')));
  });

  testWidgets('pull down on the first post refreshes', (tester) async {
    final server = FakeServer()
      ..on('GET /v1/timeline', (_) => page([post('p1'), post('p2')]));
    await pumpApp(tester, server, size: phone);
    await tester.fling(feed, const Offset(0, 600), 1000);
    await tester.pumpAndSettle();
    expect(server.called('GET /v1/timeline'), hasLength(2));
    expect(find.text('Idea p1'), findsOneWidget);
  });

  testWidgets('a feed video opens full screen with sound, and comes back', (
    tester,
  ) async {
    final videos = Videos();
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => page([post('v1', explainer: video('v1')), post('p2')]),
      );
    await pumpApp(tester, server, size: phone, overrides: [videos.override]);
    final v1 = videos.byId['v1']!;
    expect(v1.value.volume, 0);

    await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-fullscreen-page')), findsOneWidget);
    // Same playback, now with sound, and it keeps playing.
    expect(v1.value.isPlaying, isTrue);
    expect(v1.value.volume, 1);

    // Tap to pause and play.
    await tester.tap(find.bySemanticsLabel(RegExp(r'Tap to pause$')));
    await tester.pump();
    expect(v1.value.isPlaying, isFalse);
    await tester.tap(find.bySemanticsLabel(RegExp(r'Tap to play$')));
    await tester.pump();
    expect(v1.value.isPlaying, isTrue);

    await tester.tap(find.byKey(const ValueKey('video-exit-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-fullscreen-page')), findsNothing);
    // Back in the feed: playing again, muted as the feed was.
    expect(v1.value.isPlaying, isTrue);
    expect(v1.value.volume, 0);
  });
}

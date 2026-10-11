import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/timeline/timeline_screen.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/layout/adaptive.dart';
import 'package:reborn/src/router.dart';
import 'package:reborn/src/tv/tv_mode.dart';
import 'package:video_player/video_player.dart';

import 'fake_server.dart';
import 'fixtures.dart';

const phone = Size(400, 1400);
const tabletPortrait = Size(820, 1180);
const tabletLandscape = Size(1180, 820);
const desktop = Size(1400, 900);
const tv = Size(1920, 1080);
const tvPrefs = <String, Object>{
  'onboarding.done': true,
  'appearance.tv_layout': 'on',
};

Map<String, dynamic> post(String id, {Map<String, dynamic>? explainer}) =>
    postJson(
      cardJsonWith({
        'id': id,
        'title': 'Idea $id',
        'quote': null,
        'explainer': ?explainer,
      }),
    );

FakeServer server({List<String> timeline = const ['p1', 'p2', 'p3']}) =>
    FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [for (final id in timeline) post(id)],
          'next_cursor': null,
        },
      )
      ..on(
        'GET /v1/discover',
        (_) => {
          'trending': [post('t1'), post('t2')],
          'new': [post('n1')],
        },
      );

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
  Future<void> seekTo(Duration position) async {}
}

/// The location on top, including pages pushed on top of a tab.
String topPath(ProviderContainer c) => c
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .last
    .matchedLocation;

String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

void main() {
  group('window size classes', () {
    test('Material breakpoints', () {
      expect(WindowSize.forWidth(599), WindowSize.compact);
      expect(WindowSize.forWidth(600), WindowSize.medium);
      expect(WindowSize.forWidth(839), WindowSize.medium);
      expect(WindowSize.forWidth(840), WindowSize.expanded);
      expect(WindowSize.forWidth(1199), WindowSize.expanded);
      expect(WindowSize.forWidth(1200), WindowSize.large);
    });

    testWidgets('phone: swipe feed and bottom navigation', (tester) async {
      await pumpApp(tester, server(), size: phone);
      expect(find.byKey(const ValueKey('swipe-feed')), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byKey(const ValueKey('timeline-grid')), findsNothing);
    });

    testWidgets('tablet portrait: rail and a two-column grid', (tester) async {
      await pumpApp(tester, server(), size: tabletPortrait);
      expect(find.byKey(const ValueKey('swipe-feed')), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-grid')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-side-panel')), findsNothing);
      // p1 and p2 side by side, p3 on the next row.
      final p1 = tester.getRect(find.byKey(const ValueKey('timeline-p1')));
      final p2 = tester.getRect(find.byKey(const ValueKey('timeline-p2')));
      final p3 = tester.getRect(find.byKey(const ValueKey('timeline-p3')));
      expect(p2.top, p1.top);
      expect(p2.left, greaterThan(p1.right - 1));
      expect(p3.top, greaterThan(p1.bottom - 1));
      expect(p1.width, greaterThanOrEqualTo(kGridMinColumnWidth));
    });

    testWidgets('tablet landscape: one column with a side panel', (
      tester,
    ) async {
      await pumpApp(tester, server(), size: tabletLandscape);
      expect(find.byKey(const ValueKey('timeline-column')), findsOneWidget);
      final panel = find.byKey(const ValueKey('timeline-side-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Make Reborn yours')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Idea t1')),
        findsOneWidget,
      );
    });

    testWidgets('large: grid and side panel', (tester) async {
      await pumpApp(tester, server(), size: desktop);
      expect(find.byKey(const ValueKey('timeline-grid')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-side-panel')), findsOneWidget);
    });

    testWidgets('rotating a tablet switches grid and side panel', (
      tester,
    ) async {
      await pumpApp(tester, server(), size: tabletPortrait);
      expect(find.byKey(const ValueKey('timeline-grid')), findsOneWidget);
      tester.view.physicalSize = tabletLandscape;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timeline-column')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-side-panel')), findsOneWidget);
      tester.view.physicalSize = tabletPortrait;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timeline-grid')), findsOneWidget);
    });

    testWidgets('expanded: Discover opens an idea in the right pane', (
      tester,
    ) async {
      final c = await pumpApp(tester, server(), size: tabletLandscape);
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('two-pane')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-detail')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('discover-post-t1')));
      await tester.pumpAndSettle();
      expect(topPath(c), '/discover'); // stayed on the list
      expect(find.byKey(const ValueKey('empty-detail')), findsNothing);
      expect(find.byKey(const ValueKey('card-page-card')), findsOneWidget);
      expect(find.text('Idea t1'), findsNWidgets(2)); // list + detail

      await tester.tap(find.byKey(const ValueKey('discover-post-t2')));
      await tester.pumpAndSettle();
      expect(find.text('Idea t2'), findsNWidgets(2));
      expect(find.text('Idea t1'), findsOneWidget);
    });

    testWidgets('medium: Discover pushes the card page instead', (
      tester,
    ) async {
      final c = await pumpApp(tester, server(), size: tabletPortrait);
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('two-pane')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('discover-post-t1')));
      await tester.pumpAndSettle();
      expect(topPath(c), '/cards/t1');
      // Centred card with margins, at most 720 wide.
      final card = tester.getRect(find.byKey(const ValueKey('card-page-card')));
      expect(card.width, lessThanOrEqualTo(720));
      expect(card.left, greaterThanOrEqualTo(24));
    });
  });

  group('TV', () {
    test('the URL can force the TV layout for a preview', () {
      expect(tvOverrideFromEnvironment(Uri.parse('http://x/?tv=1')), isTrue);
      expect(tvOverrideFromEnvironment(Uri.parse('http://x/?tv=0')), isFalse);
      expect(tvOverrideFromEnvironment(Uri.parse('http://x/')), isNull);
    });

    testWidgets('the Settings toggle turns the TV layout on and off', (
      tester,
    ) async {
      final c = await pumpApp(tester, server(), size: tv);
      expect(find.byKey(const ValueKey('tv-rows')), findsNothing);
      await push(tester, c, '/settings');
      final toggle = find.byKey(const ValueKey('tv-layout'));
      await tester.ensureVisible(toggle);
      await tester.tap(find.descendant(of: toggle, matching: find.text('On')));
      await tester.pumpAndSettle();
      expect(c.read(isTvProvider), isTrue);
      c.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-rows')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-rail')), findsOneWidget);

      c.read(tvLayoutProvider.notifier).set(TvLayout.off);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-rows')), findsNothing);
      expect(find.byKey(const ValueKey('timeline-grid')), findsOneWidget);
    });

    testWidgets('auto follows what the device reports', (tester) async {
      await pumpApp(
        tester,
        server(),
        size: tv,
        overrides: [tvDetectedProvider.overrideWithValue(true)],
      );
      expect(find.byKey(const ValueKey('tv-rows')), findsOneWidget);
    });

    testWidgets('rows; arrows move focus, Enter opens, Escape returns', (
      tester,
    ) async {
      final c = await pumpApp(tester, server(), prefs: tvPrefs, size: tv);
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('Trending this week'), findsOneWidget);
      expect(find.text('New ideas'), findsOneWidget);
      // The first card has focus, with no touch needed.
      expect(focusLabel(), 'tv-card for-you/0');

      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focusLabel(), 'tv-card for-you/1');
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowRight); // the row ends
      expect(focusLabel(), 'tv-card for-you/2');
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel(), 'tv-card for-you/1');

      // Down keeps the column: the card below, not the row's first.
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusLabel(), 'tv-card trending/1');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusLabel(), 'tv-card new/0'); // the row has one card
      // Up returns to where each row was left.
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusLabel(), 'tv-card for-you/1');

      // Left from the first card reaches the navigation rail.
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel(), 'tv-card for-you/0');
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel(), isNot(startsWith('tv-card')));
      expect(
        find.byKey(const ValueKey('tv-focus-ring')),
        findsOneWidget,
        reason: 'the rail item gets the amber ring',
      );
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focusLabel(), startsWith('tv-card'));

      // Enter opens the idea; Escape (Back) returns with focus restored.
      final before = focusLabel();
      await key(tester, LogicalKeyboardKey.enter);
      expect(topPath(c), startsWith('/tv/cards/'));
      expect(find.byKey(const ValueKey('tv-card-title')), findsOneWidget);
      expect(focusLabel(), isNot(startsWith('tv-card ')));
      await key(tester, LogicalKeyboardKey.escape);
      expect(topPath(c), '/home');
      expect(focusLabel(), before);
    });

    testWidgets('video: full screen, Select plays and pauses, Back exits', (
      tester,
    ) async {
      final s = server(timeline: [])
        ..on(
          'GET /v1/timeline',
          (_) => {
            'posts': [
              post(
                'v1',
                explainer: {
                  'kind': 'animated',
                  'video_url': '/media/v1.mp4',
                  'poster_url': '/media/v1.jpg',
                  'duration_s': 42,
                  'width': 720,
                  'height': 1280,
                },
              ),
            ],
            'next_cursor': null,
          },
        );
      final videos = <FakeVideo>[];
      final c = await pumpApp(
        tester,
        s,
        prefs: tvPrefs,
        size: tv,
        overrides: [
          videoControllerFactoryProvider.overrideWithValue((url) {
            final v = FakeVideo(url);
            videos.add(v);
            return v;
          }),
        ],
      );
      expect(focusLabel(), 'tv-card for-you/0');
      await key(tester, LogicalKeyboardKey.select);
      expect(topPath(c), '/tv/cards/v1');
      // Play is focused first on a video idea.
      await key(tester, LogicalKeyboardKey.select);
      expect(topPath(c), '/tv/video/v1');
      expect(videos.single.value.isPlaying, isTrue);
      expect(find.byKey(const ValueKey('tv-video-paused')), findsNothing);

      await key(tester, LogicalKeyboardKey.select);
      expect(videos.single.value.isPlaying, isFalse);
      expect(find.byKey(const ValueKey('tv-video-paused')), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(videos.single.value.isPlaying, isTrue);

      // The remote's Back button (Android's system back).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(topPath(c), '/tv/cards/v1');
      await key(tester, LogicalKeyboardKey.escape);
      expect(topPath(c), '/home');
    });

    testWidgets('the card page scrolls its text with up and down', (
      tester,
    ) async {
      await pumpApp(tester, server(), prefs: tvPrefs, size: tv);
      await key(tester, LogicalKeyboardKey.enter);
      // Without a video, Read has focus; Select moves focus to the text.
      await key(tester, LogicalKeyboardKey.enter);
      expect(focusLabel(), 'tv-card-body');
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel(), isNot('tv-card-body'));
    });
  });
}

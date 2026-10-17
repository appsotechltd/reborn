// Fixes for issues found in the app walkthrough QA.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/post/share.dart';
import 'package:reborn/src/layout/adaptive.dart';
import 'package:reborn/src/features/admin/admin_screen.dart';
import 'package:reborn/src/features/card/card_view.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/features/streak/streak_card.dart';
import 'package:reborn/src/router.dart';
import 'package:video_player/video_player.dart';

import 'fake_server.dart';
import 'fixtures.dart';

const moderatorPrefs = <String, Object>{
  'onboarding.done': true,
  'auth.token': 'tok',
  'auth.user':
      '{"id":"u9","email":"m@b.com","handle":"carol","display_name":"Carol",'
      '"bio":"","role":"moderator","topics":[]}',
};

const tvPrefs = <String, Object>{
  'onboarding.done': true,
  'appearance.tv_layout': 'on',
};

const video = <String, dynamic>{
  'kind': 'animated',
  'video_url': '/media/v1.mp4',
  'poster_url': '/media/v1.jpg',
  'duration_s': 65,
  'width': 720,
  'height': 1280,
};

Map<String, dynamic> videoPost(String id) => postJson(
  cardJsonWith({
    'id': id,
    'title': 'Idea $id',
    'topic': 'relationships',
    'quote': null,
    'explainer': video,
  }),
);

/// A video that never loads, like an H.264 file in a browser without it.
class BrokenVideo extends VideoPlayerController {
  BrokenVideo(super.url) : super.networkUrl();

  @override
  Future<void> initialize() async => throw PlatformException(code: 'codec');
}

void main() {
  group('streak', () {
    test('goal met reads as a count against the goal, not "31 of 3"', () {
      expect(
        streakTodayText(const Streak(today: 31, goal: 3, goalMet: true)),
        'Goal met · 31 ideas today (goal 3)',
      );
      expect(
        streakTodayText(const Streak(today: 1, goal: 1, goalMet: true)),
        'Goal met · 1 idea today (goal 1)',
      );
      expect(
        streakTodayText(const Streak(today: 1, goal: 3)),
        '1 of 3 ideas today',
      );
    });
  });

  group('quotes', () {
    test('wrapped in curly quotes unless they carry their own marks', () {
      expect(displayQuote(' Begin the morning. '), '“Begin the morning.”');
      expect(
        displayQuote('"Begin, friend," said he, "and set it up."'),
        '"Begin, friend," said he, "and set it up."',
      );
      expect(displayQuote('“Already quoted.”'), '“Already quoted.”');
      // Single marks inside are speech, not a wrapper.
      expect(displayQuote('‘Yes,’ says the man.'), '“‘Yes,’ says the man.”');
    });
  });

  testWidgets('video poster: Play and duration share the bottom row', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/posts/v1', (_) => videoPost('v1'))
      ..on('POST /v1/cards/v1/view', (_) => const Reply.empty());
    await pumpApp(tester, s, location: '/cards/v1', size: const Size(400, 900));
    final player = tester.getRect(find.byType(ExplainerPlayer));
    final play = tester.getRect(find.byKey(const ValueKey('video-play')));
    final duration = tester.getRect(find.text('1:05'));
    // Both in the bottom band, clear of the poster's own title and topic
    // label at its top; the duration beside Play, not in the top corner.
    expect(play.top, greaterThan(player.top + player.height * 0.75));
    expect(duration.center.dy, closeTo(play.center.dy, 2));
    expect(duration.left, greaterThan(play.right));
    // No centred play badge over the poster's title.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video-play')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('count buttons have names, not just numbers', (tester) async {
    final s = FakeServer()
      ..on(
        'GET /v1/posts/p1',
        (_) => postJson(cardJson(), comments: 2, favorites: 3, shares: 1),
      )
      ..on('POST /v1/cards/p1/view', (_) => const Reply.empty());
    final handle = tester.ensureSemantics();
    await pumpApp(tester, s, location: '/cards/p1');
    expect(find.bySemanticsLabel('Favourite, 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Comments, 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Share, 1'), findsOneWidget);
    final fav = tester.getSemantics(find.bySemanticsLabel('Favourite, 3'));
    expect(fav.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  group('dashboard', () {
    final stats = {
      'users': {'total': 11, 'new_7d': 2},
      'daily': [
        {'day': '2026-10-10', 'signups': 2, 'active': 11},
        {'day': '2026-10-11', 'signups': 1, 'active': 4},
      ],
    };

    testWidgets('phone: stat tiles fill the width in two columns', (
      tester,
    ) async {
      final s = FakeServer()..on('GET /v1/admin/stats', (_) => stats);
      await pumpApp(
        tester,
        s,
        prefs: moderatorPrefs,
        location: '/admin',
        size: const Size(390, 2400),
      );
      final first = tester.getRect(find.byKey(const ValueKey('stat-Users')));
      final second = tester.getRect(
        find.byKey(const ValueKey('stat-New (7d)')),
      );
      expect(second.top, first.top);
      // 16 px page padding each side, 8 px between.
      expect(first.left, 16);
      expect(second.right, 390 - 16);
    });

    testWidgets('chart label uses a text colour from the theme', (
      tester,
    ) async {
      final s = FakeServer()..on('GET /v1/admin/stats', (_) => stats);
      final c = await pumpApp(
        tester,
        s,
        prefs: {...moderatorPrefs, 'appearance.theme_mode': 'dark'},
        location: '/admin',
      );
      expect(c, isNotNull);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('daily-chart')),
      );
      final painter = paint.painter! as DailyChartPainter;
      final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey('daily-chart'))),
      ).colorScheme;
      expect(painter.labelColor, scheme.onSurfaceVariant);
      expect(painter.labelColor, isNot(painter.gridColor));
    });
  });

  testWidgets('moderation lists comments reported as spam; Hide hides it', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/moderation/queue', (_) => {'contributions': <Object>[]})
      ..on(
        'GET /v1/moderation/comments',
        (_) => {
          'comments': [
            {
              'id': 'c9',
              'post_id': 'p1',
              'parent_id': null,
              'body': 'Check out my channel for crypto tips!!!',
              'author': {'id': 'u5', 'handle': 'spammy', 'display_name': 'Sp'},
              'created_at': '2026-10-10T09:00:00Z',
              'status': 'hidden',
              'reports': 3,
              'reasons': ['spam', 'spam', 'spam'],
            },
          ],
        },
      )
      ..on('POST /v1/moderation/comments/c9/hide', (_) => const Reply.empty());
    await pumpApp(tester, s, prefs: moderatorPrefs, location: '/moderation');
    expect(find.text('No contributions are waiting.'), findsOneWidget);
    expect(
      find.text('Check out my channel for crypto tips!!!'),
      findsOneWidget,
    );
    expect(find.text('3 reports: spam'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hide'));
    await tester.pumpAndSettle();
    expect(s.called('POST /v1/moderation/comments/c9/hide'), hasLength(1));
    expect(find.text('Hidden ✓'), findsOneWidget);
  });

  group('TV', () {
    FakeServer tvServer() => FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [videoPost('v1')],
          'next_cursor': null,
        },
      )
      ..on(
        'GET /v1/discover',
        (_) => {
          'trending': [videoPost('t1')],
        },
      );

    testWidgets('a video tile keeps its play mark in the corner', (
      tester,
    ) async {
      await pumpApp(
        tester,
        tvServer(),
        prefs: tvPrefs,
        size: const Size(1920, 1080),
      );
      final mark = find.byKey(const ValueKey('tv-tile-play')).first;
      final poster = find.ancestor(of: mark, matching: find.byType(Stack));
      final box = tester.getRect(poster.first);
      final at = tester.getRect(mark);
      expect(at.right, closeTo(box.right - 8, 1));
      expect(at.bottom, closeTo(box.bottom - 8, 1));
    });

    testWidgets('the idea page shows its topic once', (tester) async {
      final s = tvServer()
        ..on('GET /v1/posts/v1', (_) => videoPost('v1'))
        ..on('POST /v1/cards/v1/view', (_) => const Reply.empty());
      final c = await pumpApp(
        tester,
        s,
        prefs: tvPrefs,
        size: const Size(1920, 1080),
      );
      await push(tester, c, '/tv/cards/v1');
      expect(find.byKey(const ValueKey('tv-card-title')), findsOneWidget);
      expect(find.text('RELATIONSHIPS'), findsOneWidget);
    });

    testWidgets("a video that can't play says so inside its band", (
      tester,
    ) async {
      final s = tvServer()
        ..on('GET /v1/posts/v1', (_) => videoPost('v1'))
        ..on('POST /v1/cards/v1/view', (_) => const Reply.empty());
      final c = await pumpApp(
        tester,
        s,
        prefs: tvPrefs,
        size: const Size(1920, 1080),
        overrides: [
          videoControllerFactoryProvider.overrideWithValue(BrokenVideo.new),
        ],
      );
      c
          .read(routerProvider)
          .push('/tv/video/v1', extra: Post.fromJson(videoPost('v1')).card);
      await tester.pumpAndSettle();
      final band = tester.getRect(
        find.byKey(const ValueKey('tv-video-failed')),
      );
      expect(band.width, lessThanOrEqualTo(520));
      // Inside the poster, which fills the height at its own shape.
      final poster = 1080 * 720 / 1280;
      expect(band.left, greaterThanOrEqualTo((1920 - poster) / 2));
      expect(band.right, lessThanOrEqualTo((1920 + poster) / 2));
      for (final text in [
        "This video couldn't be played here.",
        'Press Back to leave.',
      ]) {
        final r = tester.getRect(find.text(text));
        expect(
          band.contains(r.topLeft) && band.contains(r.bottomRight),
          isTrue,
        );
      }
    });

    testWidgets("Settings speaks of the TV's setting, not the phone's", (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        tvServer(),
        prefs: tvPrefs,
        size: const Size(1920, 1080),
      );
      await push(tester, c, '/settings');
      expect(
        // Dark is the default, so the hint names the TV, not the phone.
        find.text('Always dark, whatever your TV uses.'),
        findsOneWidget,
      );
      expect(find.textContaining("phone's"), findsNothing);
    });
  });

  group('walkthrough majors', () {
    testWidgets('opening the inbox fetches it again', (tester) async {
      var replies = 0;
      final s = FakeServer()
        ..on(
          'GET /v1/notifications',
          (_) => {
            'notifications': [
              for (var i = 0; i < replies; i++)
                {
                  'id': 'n$i',
                  'kind': 'follow',
                  'text': 'Ada started following you',
                  'actor': {'id': 'u2', 'handle': 'ada', 'display_name': 'A'},
                  'created_at': '2026-10-11T09:00:00Z',
                },
            ],
            'unread': replies,
          },
        )
        ..on('POST /v1/notifications/read', (_) => const Reply.empty());
      final c = await pumpApp(tester, s, prefs: signedInPrefs);
      final before = s.called('GET /v1/notifications').length;
      replies = 1; // arrives after the bell first loaded
      await push(tester, c, '/notifications');
      expect(s.called('GET /v1/notifications').length, greaterThan(before));
      expect(find.text('Ada started following you'), findsOneWidget);
    });

    testWidgets('a card opened by link has a way Home', (tester) async {
      final s = FakeServer()
        ..on('GET /v1/posts/p1', (_) => postJson(cardJson()))
        ..on('POST /v1/cards/p1/view', (_) => const Reply.empty());
      final c = await pumpApp(tester, s);
      c.read(routerProvider).go('/cards/p1');
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exit-home')));
      await tester.pumpAndSettle();
      expect(currentPath(c), '/home');

      // Pushed on top of Home it has the usual Back instead.
      await push(tester, c, '/cards/p1');
      expect(find.byKey(const ValueKey('exit-home')), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('with no share sheet, Share copies the link and says so', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      final s = FakeServer()
        ..on('GET /v1/posts/p1', (_) => postJson(cardJson(), shares: 2))
        ..on('POST /v1/cards/p1/view', (_) => const Reply.empty())
        ..on(
          'POST /v1/posts/meditations-marcus-aurelius--01/share',
          (_) => const Reply.empty(),
        );
      await pumpApp(tester, s, location: '/cards/p1', sharer: _NoShareSheet());
      await tester.tap(find.byKey(const ValueKey('post-share')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Link copied — paste it anywhere'), findsOneWidget);
      expect(copied.single, contains('/ideas/'));
      final shares = s.calls.where((c) => c.path.endsWith('/share'));
      expect(shares.single.body, {'channel': 'copy_link'});
    });

    testWidgets('two panes: the list keeps its semantics and focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final first = FocusNode();
      addTearDown(first.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListDetail(
            selectedId: 'a',
            empty: const SizedBox(),
            list: Scaffold(
              body: ListView(
                children: [
                  ListTile(
                    focusNode: first,
                    title: const Text('Item A'),
                    onTap: () {},
                  ),
                  ListTile(title: const Text('Item B'), onTap: () {}),
                ],
              ),
            ),
            detail: () => Scaffold(
              appBar: AppBar(
                title: const Text('Detail A'),
                actions: [
                  IconButton(
                    tooltip: 'Options',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      first.requestFocus();
      await tester.pumpAndSettle();
      expect(find.text('Detail A'), findsOneWidget);
      // A screen reader can still reach the list.
      expect(find.bySemanticsLabel('Item B'), findsOneWidget);
      expect(find.bySemanticsLabel('Detail A'), findsOneWidget);
      // Opening the detail doesn't pull focus onto its buttons.
      expect(first.hasFocus, isTrue);
      handle.dispose();
    });

    testWidgets('TV rail: Down stays in the rail, Left goes nowhere', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeServer()..on(
          'GET /v1/timeline',
          (_) => {
            'posts': [postJson(cardJson())],
            'next_cursor': null,
          },
        ),
        prefs: tvPrefs,
        size: const Size(1920, 1080),
      );
      Future<void> press(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pumpAndSettle();
      }

      bool inRail() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<NavigationRail>() !=
          null;

      await press(LogicalKeyboardKey.arrowLeft);
      expect(inRail(), isTrue);
      for (var i = 0; i < 8; i++) {
        await press(LogicalKeyboardKey.arrowDown);
        expect(inRail(), isTrue, reason: 'Down $i left the rail');
      }
      final at = FocusManager.instance.primaryFocus;
      await press(LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus, at);
      for (var i = 0; i < 8; i++) {
        await press(LogicalKeyboardKey.arrowUp);
        expect(inRail(), isTrue);
      }
    });

    testWidgets('TV: opening Stashes focuses a stash; OK keeps it there', (
      tester,
    ) async {
      final s = FakeServer()
        ..on(
          'GET /v1/timeline',
          (_) => {
            'posts': [postJson(cardJson())],
            'next_cursor': null,
          },
        )
        ..on(
          'GET /v1/stashes',
          (_) => {
            'stashes': [
              {'id': 's1', 'name': 'Deep focus', 'card_count': 2},
            ],
          },
        )
        ..on(
          'GET /v1/stashes/s1',
          (_) => {
            'stash': {'id': 's1', 'name': 'Deep focus', 'card_count': 0},
            'cards': <Object>[],
          },
        );
      await pumpApp(
        tester,
        s,
        prefs: {...signedInPrefs, 'appearance.tv_layout': 'on'},
        size: const Size(1920, 1080),
      );
      Future<void> press(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.arrowLeft);
      await press(LogicalKeyboardKey.arrowDown);
      await press(LogicalKeyboardKey.arrowDown); // Stashes
      await press(LogicalKeyboardKey.enter);
      final item = FocusManager.instance.primaryFocus!;
      expect(item, isNot(isA<FocusScopeNode>()), reason: 'focus is visible');
      expect(
        item.context!.findAncestorWidgetOfExactType<NavigationRail>(),
        isNull,
      );
      final rect = tester.getRect(find.text('Deep focus').first);
      expect(item.rect.top, lessThanOrEqualTo(rect.top));
      expect(item.rect.bottom, greaterThanOrEqualTo(rect.bottom));

      // OK opens it on the right without moving focus to its options.
      await press(LogicalKeyboardKey.enter);
      expect(FocusManager.instance.primaryFocus, item);
      expect(find.text('Rename'), findsNothing);
      // Left goes back to the rail, never to the right.
      await press(LogicalKeyboardKey.arrowLeft);
      expect(
        FocusManager.instance.primaryFocus!.rect.center.dx,
        lessThan(item.rect.left),
      );
    });

    testWidgets('TV idea page: Back from the text returns to the buttons', (
      tester,
    ) async {
      final s = FakeServer()
        ..on(
          'GET /v1/timeline',
          (_) => {
            'posts': [postJson(cardJson())],
            'next_cursor': null,
          },
        )
        ..on('POST /v1/cards/meditations-marcus-aurelius--01/view', (_) {
          return const Reply.empty();
        });
      final c = await pumpApp(
        tester,
        s,
        prefs: tvPrefs,
        size: const Size(1920, 1080),
      );
      Future<void> press(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.enter); // open the idea
      await press(LogicalKeyboardKey.enter); // Read: focus the text
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-card-body');
      await press(LogicalKeyboardKey.escape);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-read');
      expect(topPath(c), startsWith('/tv/cards/'));
    });

    testWidgets('the welcome screen offers Sign in', (tester) async {
      final c = await pumpApp(tester, FakeServer(), prefs: const {});
      final link = find.byKey(const ValueKey('onboarding-sign-in'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(topPath(c), '/signin');
    });
  });
}

/// The location on top, including pages pushed on top of a tab.
String topPath(ProviderContainer c) => c
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .last
    .matchedLocation;

/// A browser without the Web Share API.
class _NoShareSheet implements Sharer {
  @override
  Future<bool> share({
    required String text,
    required String subject,
    Rect? origin,
  }) async => throw UnsupportedError('no share sheet');

  @override
  Future<bool> shareFile({
    required Uri url,
    required String fileName,
    required String mimeType,
    required String text,
    Rect? origin,
  }) async => throw UnsupportedError('no share sheet');
}

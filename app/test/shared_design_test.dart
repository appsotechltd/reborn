import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/discover/discover_screen.dart';
import 'package:reborn/src/theme.dart';

import 'fake_server.dart';
import 'fixtures.dart';

/// The shared design with the web: card page order, the health note before
/// the reading, the streak's best run and goal, and Discover's post cards.

const phone = Size(390, 1400);

double _top(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

void main() {
  group('card page', () {
    Future<void> openCard(WidgetTester t, Map<String, dynamic> card) async {
      final server = FakeServer()
        ..on('GET /v1/posts/${card['id']}', (_) => postJson(card));
      await pumpApp(t, server, size: phone, location: '/cards/${card['id']}');
    }

    testWidgets('topic, then title, then the source line, as on the feed', (
      t,
    ) async {
      final card = cardJsonWith({});
      await openCard(t, card);
      final tag = find.byType(CategoryTag).first;
      final title = find.byKey(const ValueKey('card-title'));
      final byline = find.byKey(const ValueKey('card-byline'));
      expect(tag, findsOneWidget);
      expect(title, findsOneWidget);
      expect(byline, findsOneWidget);
      expect(_top(t, tag), lessThan(_top(t, title)));
      expect(_top(t, title), lessThan(_top(t, byline)));
      expect(
        _top(t, byline),
        lessThan(_top(t, find.text(card['body'] as String))),
      );
      // The source line names the book and its author.
      expect(
        find.descendant(of: byline, matching: find.text('Meditations')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: byline, matching: find.text('Marcus Aurelius')),
        findsOneWidget,
      );
    });

    testWidgets('the title is article-sized: larger than the feed title', (
      t,
    ) async {
      await openCard(t, cardJsonWith({}));
      final style = t
          .widget<Text>(find.byKey(const ValueKey('card-title')))
          .style!;
      final feed = Theme.of(t.element(find.byKey(const ValueKey('card-title'))))
          .textTheme
          .headlineSmall!;
      expect(style.fontFamily, 'Fraunces');
      expect(style.fontSize, greaterThan(feed.fontSize!));
      expect(style.fontSize, 30);
    });

    testWidgets('the health note comes before the body and Apply it', (
      t,
    ) async {
      final card = cardJsonWith({
        'id': 'nhs-sleep--01',
        'topic': 'health',
        'health': true,
        'disclaimer': healthDisclaimer,
        'quote': null,
      });
      await openCard(t, card);
      final note = find.byKey(const ValueKey('card-disclaimer'));
      expect(note, findsOneWidget);
      expect(
        _top(t, find.byKey(const ValueKey('card-byline'))),
        lessThan(_top(t, note)),
      );
      expect(
        _top(t, note),
        lessThan(_top(t, find.text(card['body'] as String))),
      );
      expect(_top(t, note), lessThan(_top(t, find.text('APPLY IT'))));
    });
  });

  group('streak', () {
    FakeServer streakServer({int current = 2, int longest = 9}) => FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [postJson(cardJsonWith({}))],
          'next_cursor': null,
        },
      )
      ..on(
        'GET /v1/me/streak',
        (_) => {
          'current': current,
          'longest': longest,
          'today': 1,
          'goal': 3,
          'last_days': <Object>[],
        },
      )
      ..on(
        'PATCH /v1/me',
        (c) => {
          'id': 'u1',
          'email': 'a@b.com',
          'handle': 'ada',
          'display_name': 'Ada',
          'bio': '',
          'role': 'member',
          'topics': <String>[],
          'daily_goal': c.body['daily_goal'],
        },
      );

    testWidgets('shows the best run when it is longer', (t) async {
      await pumpApp(t, streakServer(), size: phone, prefs: signedInPrefs);
      await openStreak(t);
      expect(find.byKey(const ValueKey('streak-card')), findsOneWidget);
      expect(find.textContaining('2-day streak'), findsOneWidget);
      expect(find.textContaining('best 9'), findsOneWidget);
    });

    testWidgets('no best when this run is the best', (t) async {
      await pumpApp(
        t,
        streakServer(current: 4, longest: 4),
        size: phone,
        prefs: signedInPrefs,
      );
      await openStreak(t);
      expect(find.textContaining('4-day streak'), findsOneWidget);
      expect(find.textContaining('best'), findsNothing);
    });

    testWidgets('Change goal picks a new daily goal and saves it', (t) async {
      final server = streakServer();
      await pumpApp(t, server, size: phone, prefs: signedInPrefs);
      await openStreak(t);
      await t.tap(find.byKey(const ValueKey('change-goal')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-picker')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('goal-5')));
      await t.pumpAndSettle();
      expect(server.called('PATCH /v1/me').single.body, {'daily_goal': 5});
      expect(find.byKey(const ValueKey('goal-picker')), findsNothing);
      // The streak is fetched again for the new goal.
      expect(server.called('GET /v1/me/streak').length, greaterThan(1));
      // Let the feed send its "seen" batch before the app is torn down.
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
    });
  });

  group('discover', () {
    testWidgets('trending and new posts are cards with excerpt, credit and '
        'counts', (t) async {
      final long = List.filled(40, 'word').join(' ');
      final server = FakeServer()
        ..on(
          'GET /v1/discover',
          (_) => {
            'trending': [
              postJson(
                cardJsonWith({'id': 't1', 'title': 'Idea t1', 'body': long}),
                reactions: {'insightful': 2, 'love': 1},
                comments: 1,
                favorites: 4,
              ),
            ],
            'new': [
              postJson(cardJsonWith({'id': 'n1', 'title': 'Idea n1'})),
            ],
          },
        );
      await pumpApp(t, server, size: phone, location: '/discover');
      final trending = find.byKey(const ValueKey('discover-post-t1'));
      expect(trending, findsOneWidget);
      Finder inside(Finder f, Finder m) => find.descendant(of: f, matching: m);
      expect(inside(trending, find.byType(CategoryTag)), findsOneWidget);
      expect(inside(trending, find.text('Idea t1')), findsOneWidget);
      expect(inside(trending, find.text(excerpt(long))), findsOneWidget);
      expect(excerpt(long), endsWith('…'));
      expect(excerpt(long).length, lessThanOrEqualTo(130));
      expect(inside(trending, find.text(sampleCard().credit)), findsOneWidget);
      expect(
        inside(trending, find.text('3 reactions   1 comment   4 favourites')),
        findsOneWidget,
      );
      // Trending is ranked; New is not.
      expect(inside(trending, find.text('1')), findsOneWidget);
      final fresh = find.byKey(const ValueKey('discover-post-n1'));
      expect(fresh, findsOneWidget);
      expect(
        inside(fresh, find.text('0 reactions   0 comments   0 favourites')),
        findsOneWidget,
      );
    });

    test('excerpt keeps short text and cuts long text at a word', () {
      expect(excerpt('  Short   text. '), 'Short text.');
      final cut = excerpt(List.filled(60, 'abcd').join(' '));
      expect(cut, endsWith('abcd…'));
    });
  });

  test('light reactions use the accessible amber', () {
    expect(CandlelightTokens.light.react, const Color(0xFF9A5B0E));
  });
}

/// On phones the streak sits behind the flame chip in the top bar.
Future<void> openStreak(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('streak-chip')));
  await t.pumpAndSettle();
}

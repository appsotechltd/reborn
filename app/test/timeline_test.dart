import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'fixtures.dart';

Map<String, dynamic> post(
  String id, {
  bool? seen,
  Map<String, dynamic>? reason,
}) => postJson(
  cardJsonWith({'id': id, 'title': 'Idea $id', 'quote': null}),
  viewer: seen == null
      ? null
      : {'reaction': null, 'favorited': false, 'seen': seen},
  reason: reason,
);

void main() {
  testWidgets('signed in: reasons, caught-up line, and posts marked seen', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [
            post(
              'p1',
              seen: false,
              reason: {'kind': 'source', 'label': 'Meditations'},
            ),
            post(
              'p2',
              seen: false,
              reason: {'kind': 'favorite', 'label': 'Bob'},
            ),
            post('p3', seen: true, reason: {'kind': 'topic', 'label': 'Money'}),
          ],
          'next_cursor': null,
        },
      )
      ..on('POST /v1/seen', (_) => const Reply.empty());
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      size: const Size(800, 4000),
    );

    expect(find.text('Idea p1'), findsOneWidget);
    expect(find.text('From Meditations'), findsOneWidget);
    expect(find.text('Bob favourited this'), findsOneWidget);
    expect(find.text('Make Reborn yours'), findsNothing);

    // "You're all caught up" sits between p2 (unseen) and p3 (seen).
    final caughtUp = tester.getTopLeft(find.text("You're all caught up")).dy;
    expect(caughtUp, greaterThan(tester.getTopLeft(find.text('Idea p2')).dy));
    expect(caughtUp, lessThan(tester.getTopLeft(find.text('Idea p3')).dy));

    // Visible for a second, then batched.
    await tester.pump(const Duration(milliseconds: 500));
    expect(server.log, isNot(contains('POST /v1/seen')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final seen = server.called('POST /v1/seen').single.body['post_ids'] as List;
    expect(seen, containsAll(['p1', 'p2']));
    expect(seen, isNot(contains('p3'))); // the server already had it
  });

  testWidgets('infinite scroll loads the next page with the cursor', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/timeline', (c) {
        if (c.query['cursor'] == 'n1') {
          return {
            'posts': [post('p3')],
            'next_cursor': null,
          };
        }
        return {
          'posts': [post('p1'), post('p2')],
          'next_cursor': 'n1',
        };
      });
    await pumpApp(tester, server, size: const Size(800, 3000));
    await tester.scrollUntilVisible(
      find.text('Idea p3'),
      500,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Idea p3'), findsOneWidget);
    expect(server.called('GET /v1/timeline').map((c) => c.query['cursor']), [
      null,
      'n1',
    ]);
    expect(find.text("That's everything for now."), findsOneWidget);
  });

  testWidgets('signed out: sign-up prompt, no seen calls, pull to refresh', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [post('p1'), post('p2')],
          'next_cursor': null,
        },
      );
    await pumpApp(tester, server);
    expect(find.text('Make Reborn yours'), findsOneWidget);
    expect(find.text("You're all caught up"), findsNothing);

    await tester.fling(
      find.text('Make Reborn yours'),
      const Offset(0, 600),
      1000,
    );
    await tester.pumpAndSettle();
    expect(server.called('GET /v1/timeline'), hasLength(2));

    await tester.pump(const Duration(seconds: 4));
    expect(server.log, isNot(contains('POST /v1/seen')));

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
  });

  testWidgets('topic chips filter the timeline', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/timeline',
        (_) => {
          'posts': [post('p1')],
          'next_cursor': null,
        },
      )
      ..on(
        'GET /v1/topics',
        (_) => {
          'topics': [
            {'slug': 'money', 'name': 'Money', 'card_count': 3},
          ],
        },
      );
    await pumpApp(tester, server);
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(server.calls.last.query['topics'], 'money');
  });

  testWidgets('the swipe feed is still reachable from the timeline', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/feed',
        (_) => {
          'cards': [cardJson()],
          'next_cursor': null,
        },
      );
    await pumpApp(tester, server);
    await tester.tap(find.byTooltip('Swipe through ideas'));
    await tester.pumpAndSettle();
    expect(find.text('Swipe ideas'), findsOneWidget);
    expect(find.text(sampleCard().title), findsOneWidget);
  });
}

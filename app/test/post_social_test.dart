import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reborn/src/features/gifts/gift_sheet.dart';

import 'fake_server.dart';
import 'fixtures.dart';

const postId = 'meditations-marcus-aurelius--01';

Map<String, dynamic> comment(
  String id,
  String body, {
  String? parent,
  String userId = 'u2',
  String handle = 'bob',
  String name = 'Bob',
}) => {
  'id': id,
  'post_id': postId,
  'parent_id': parent,
  'body': body,
  'author': {'id': userId, 'handle': handle, 'display_name': name},
  'created_at': '2026-10-10T09:00:00Z',
};

FakeServer postServer({bool signedIn = true}) {
  final s = FakeServer();
  s.on(
    'GET /v1/posts/$postId',
    (_) => postJson(
      cardJson(),
      reactions: {'love': 2},
      comments: 3,
      favorites: 4,
      shares: 1,
      viewer: signedIn
          ? {'reaction': null, 'favorited': false, 'seen': true}
          : null,
    ),
  );
  s.on('PUT /v1/posts/$postId/reaction', (_) => const Reply.empty());
  s.on('DELETE /v1/posts/$postId/reaction', (_) => const Reply.empty());
  s.on('PUT /v1/posts/$postId/favorite', (_) => const Reply.empty());
  s.on('DELETE /v1/posts/$postId/favorite', (_) => const Reply.empty());
  s.on('POST /v1/posts/$postId/share', (_) => const Reply.empty());
  s.on('POST /v1/cards/$postId/view', (_) => const Reply.empty());
  return s;
}

Finder reactionCount(String reaction, String count) => find.descendant(
  of: find.byKey(ValueKey('reaction-$reaction')),
  matching: find.text(count),
);

void main() {
  testWidgets('reactions are optimistic, one per user, tap again clears', (
    tester,
  ) async {
    final server = postServer();
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );
    expect(find.text(sampleCard().title), findsOneWidget);
    expect(find.text(sampleCard().applyIt), findsOneWidget);
    expect(reactionCount('love', '2'), findsOneWidget);
    expect(reactionCount('like', '0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reaction-love')));
    await tester.pumpAndSettle();
    expect(reactionCount('love', '3'), findsOneWidget);
    expect(server.called('PUT /v1/posts/$postId/reaction').single.body, {
      'kind': 'love',
    });

    // Switching moves the reaction.
    await tester.tap(find.byKey(const ValueKey('reaction-insightful')));
    await tester.pumpAndSettle();
    expect(reactionCount('love', '2'), findsOneWidget);
    expect(reactionCount('insightful', '1'), findsOneWidget);

    // Tapping the same one again clears it.
    await tester.tap(find.byKey(const ValueKey('reaction-insightful')));
    await tester.pumpAndSettle();
    expect(reactionCount('insightful', '0'), findsOneWidget);
    expect(server.called('DELETE /v1/posts/$postId/reaction'), hasLength(1));
  });

  testWidgets('a failed reaction rolls back and says why', (tester) async {
    final server = postServer();
    server.on(
      'PUT /v1/posts/$postId/reaction',
      (_) => Reply.error(500, 'internal', 'Something broke'),
    );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );
    await tester.tap(find.byKey(const ValueKey('reaction-like')));
    await tester.pumpAndSettle();
    expect(reactionCount('like', '0'), findsOneWidget);
    expect(find.text('Something broke'), findsOneWidget);
  });

  testWidgets('favourite toggles with its count', (tester) async {
    final server = postServer();
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );
    final fav = find.byKey(const ValueKey('post-favorite'));
    expect(find.descendant(of: fav, matching: find.text('4')), findsOneWidget);
    await tester.tap(fav);
    await tester.pumpAndSettle();
    expect(find.descendant(of: fav, matching: find.text('5')), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(fav);
    await tester.pumpAndSettle();
    expect(find.descendant(of: fav, matching: find.text('4')), findsOneWidget);
    expect(server.log, contains('PUT /v1/posts/$postId/favorite'));
    expect(server.log, contains('DELETE /v1/posts/$postId/favorite'));
  });

  testWidgets('share opens the native sheet with the title and web link', (
    tester,
  ) async {
    final server = postServer(signedIn: false);
    final sharer = FakeSharer();
    await pumpApp(tester, server, location: '/cards/$postId', sharer: sharer);
    final share = find.byKey(const ValueKey('post-share'));
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(
      sharer.shared.single,
      '${sampleCard().title}\nhttps://reborn.app/ideas/$postId',
    );
    expect(server.called('POST /v1/posts/$postId/share').single.body, {
      'channel': 'native',
    });
    expect(
      find.descendant(of: share, matching: find.text('2')),
      findsOneWidget,
    );

    // Dismissing the sheet doesn't count.
    sharer.result = false;
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/posts/$postId/share'), hasLength(1));
  });

  testWidgets('signed out, reacting or favouriting goes to sign in', (
    tester,
  ) async {
    final server = postServer(signedIn: false);
    await pumpApp(tester, server, location: '/cards/$postId');
    await tester.tap(find.byKey(const ValueKey('reaction-love')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-gift')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(server.log.where((r) => r.startsWith('PUT')), isEmpty);
  });

  testWidgets('comments: nested replies, add, reply, delete own, report', (
    tester,
  ) async {
    final server = postServer();
    final comments = [
      comment('c1', 'Great idea'),
      comment('c2', 'Mine', userId: 'u1', handle: 'ada', name: 'Ada'),
      comment('c1a', 'Agreed', parent: 'c1', handle: 'cy', name: 'Cy'),
    ];
    server.on(
      'GET /v1/posts/$postId/comments',
      (_) => {'comments': comments, 'next_cursor': null},
    );
    server.on(
      'POST /v1/posts/$postId/comments',
      (c) => Reply(
        comment(
          'c3',
          c.body['body'] as String,
          parent: c.body['parent_id'] as String?,
          userId: 'u1',
          handle: 'ada',
          name: 'Ada',
        ),
        201,
      ),
    );
    server.on('DELETE /v1/comments/c2', (_) => const Reply.empty());
    server.on('POST /v1/comments/c1/report', (_) => const Reply.empty());
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );

    final countButton = find.byKey(const ValueKey('post-comments'));
    expect(
      find.descendant(of: countButton, matching: find.text('3')),
      findsOneWidget,
    );
    await tester.tap(countButton);
    await tester.pumpAndSettle();
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Great idea'), findsOneWidget);
    // The reply is indented under its parent.
    final parentX = tester
        .getTopLeft(find.byKey(const ValueKey('comment-c1')))
        .dx;
    final replyX = tester
        .getTopLeft(find.byKey(const ValueKey('comment-c1a')))
        .dx;
    expect(replyX, greaterThan(parentX));

    // Reply to the reply: attaches to the top-level comment.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('comment-c1a')),
        matching: find.text('Reply'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replying to Bob'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('comment-field')),
      'Me too',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/posts/$postId/comments').single.body, {
      'body': 'Me too',
      'parent_id': 'c1',
    });
    expect(find.text('Me too'), findsOneWidget);

    // Delete my own comment, after confirming.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('comment-c2')),
        matching: find.byTooltip('More'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete comment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(server.log, contains('DELETE /v1/comments/c2'));
    expect(find.text('Mine'), findsNothing);

    // Report someone else's, after confirming.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('comment-c1')),
        matching: find.byTooltip('More'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report this comment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pumpAndSettle();
    expect(server.log, contains('POST /v1/comments/c1/report'));

    // Back on the post, the count followed (+1 reply, -1 deleted).
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: countButton, matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('signed out, comments are readable with a sign-in prompt', (
    tester,
  ) async {
    final server = postServer(signedIn: false);
    server.on(
      'GET /v1/posts/$postId/comments',
      (_) => {
        'comments': [comment('c1', 'Great idea')],
        'next_cursor': null,
      },
    );
    await pumpApp(tester, server, location: '/posts/$postId/comments');
    expect(find.text('Great idea'), findsOneWidget);
    expect(find.text('Sign in to comment'), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-field')), findsNothing);
  });

  testWidgets('author name opens the author screen, which can be followed', (
    tester,
  ) async {
    final server = postServer();
    server.on(
      'GET /v1/authors/Marcus%20Aurelius',
      (_) => {
        'name': 'Marcus Aurelius',
        'sources': [
          {
            'id': 'meditations-marcus-aurelius',
            'title': 'Meditations',
            'authors': ['Marcus Aurelius'],
            'kind': 'book',
            'card_count': 12,
          },
        ],
        'followers': 4,
        'is_following': false,
      },
    );
    server.on(
      'PUT /v1/follows/author/Marcus%20Aurelius',
      (_) => {'followers': 5, 'is_following': true},
    );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );
    await tester.tap(find.byKey(const ValueKey('author-Marcus Aurelius')));
    await tester.pumpAndSettle();
    expect(find.text('AUTHOR'), findsOneWidget);
    expect(find.text('12 ideas · book'), findsOneWidget);
    expect(find.text('4 followers'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-button')));
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('5 followers'), findsOneWidget);
    expect(server.log, contains('PUT /v1/follows/author/Marcus%20Aurelius'));
  });

  testWidgets('gift sheet shows tiers as coming soon without a store', (
    tester,
  ) async {
    final server = postServer();
    server.on(
      'GET /v1/gifts/tiers',
      (_) => {
        'tiers': [
          {
            'id': 'spark',
            'name': 'Spark',
            'amount_cents': 199,
            'currency': 'usd',
            'product_id': 'reborn.gift.spark',
          },
          {
            'id': 'sun',
            'name': 'Sun',
            'amount_cents': 999,
            'currency': 'usd',
            'product_id': 'reborn.gift.sun',
          },
        ],
        'providers': {'stripe': true, 'apple': true, 'google': true},
      },
    );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/cards/$postId',
    );
    await tester.tap(find.byKey(const ValueKey('post-gift')));
    await tester.pumpAndSettle();
    expect(find.text('Send a gift'), findsOneWidget);
    expect(find.text(kGiftExplainer), findsOneWidget);
    expect(find.text('Gifts are coming soon'), findsOneWidget);
    expect(find.text('Spark'), findsOneWidget);
    expect(find.text(r'$9.99'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('gift-tier-spark')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('offline, the card screen falls back to the cached card', (
    tester,
  ) async {
    final server = FakeServer()
      ..on(
        'GET /v1/posts/$postId',
        (_) => throw http.ClientException('offline'),
      );
    await pumpApp(
      tester,
      server,
      prefs: {
        'onboarding.done': true,
        'cache.card.$postId': jsonEncode(cardJson()),
      },
      location: '/cards/$postId',
    );
    expect(find.text(sampleCard().title), findsOneWidget);
    expect(find.text(sampleCard().applyIt), findsOneWidget);
    expect(find.byKey(const ValueKey('post-share')), findsOneWidget);
  });
}

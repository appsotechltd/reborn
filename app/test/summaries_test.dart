import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/summary/summary_controller.dart';

import 'fake_server.dart';
import 'fixtures.dart';

const phone = Size(400, 1400);

Map<String, dynamic> summaryJson({
  String id = 'example-book',
  String kind = 'book',
  String coverage = 'full',
  Map<String, dynamic>? viewer,
}) => {
  'id': id,
  'kind': kind,
  'title': 'The Example Book',
  'description': 'Every idea from The Example Book, in 3 one-minute parts.',
  'topic': 'personal-development',
  'topic_name': 'Personal Development',
  'coverage': coverage,
  if (kind == 'book') 'source': cardJson()['source'],
  'authors': ['Ada Example'],
  'source_count': 1,
  'part_count': 3,
  'minutes': 2,
  'published_at': '2026-10-14T00:00:00Z',
  'viewer': ?viewer,
};

Map<String, dynamic> summaryItem([Map<String, dynamic>? s]) => {
  'id': 'summary:${(s ?? summaryJson())['id']}',
  'kind': 'summary',
  'summary': s ?? summaryJson(),
};

Map<String, dynamic> detailJson({Map<String, dynamic>? viewer}) => {
  ...summaryJson(viewer: viewer),
  'parts': [
    for (var i = 1; i <= 3; i++)
      cardJsonWith({
        'id': 'example-book--0$i',
        'title': 'Part idea $i',
        'quote': null,
        'explainer': null,
      }),
  ],
};

Map<String, dynamic> post(String id) =>
    postJson(cardJsonWith({'id': id, 'title': 'Idea $id', 'quote': null}));

FakeServer serverWithSummary({Map<String, dynamic>? viewer}) {
  final server = FakeServer()
    ..on(
      'GET /v1/timeline',
      (_) => {
        'posts': [post('p1'), summaryItem(), post('p2')],
        'next_cursor': null,
      },
    )
    ..on('GET /v1/summaries/example-book', (_) => detailJson(viewer: viewer))
    ..on(
      'PUT /v1/summaries/example-book/progress',
      (c) => {
        'started': true,
        'position': (c.body as Map)['position'],
        'finished': (c.body as Map)['finished'],
      },
    );
  return server;
}

Finder get pages => find.byKey(const ValueKey('summary-pages'));

void main() {
  test('summary posts parse from the timeline and survive the cache', () {
    final page = PostPage.fromJson({
      'posts': [post('p1'), summaryItem()],
      'next_cursor': null,
    });
    expect(page.posts.map((p) => p.isSummary), [false, true]);
    final s = page.posts[1].summary!;
    expect(s.coverageLabel, 'Full summary');
    expect(s.byline, 'by Ada Example');
    expect(s.meta, '3 parts · 2 min');
    expect(page.posts[1].id, 'summary:example-book');
    final again = PostPage.fromJson(
      jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
    );
    expect(again.posts[1].summary!.title, 'The Example Book');
    expect(
      Summary.fromJson(summaryJson(coverage: 'key-ideas')).coverageLabel,
      'Key ideas summary',
    );
    final guide = Summary.fromJson({
      ...summaryJson(coverage: 'guide'),
      'cover': {
        'url': 'https://media.test/images/cards/v1/guide-x--01.webp',
        'type': 'illustration',
        'caption': 'A calm start',
      },
    });
    expect(guide.coverageLabel, 'Complete guide');
    expect(guide.cover?.caption, 'A calm start');
    expect(
      Summary.fromJson(
        jsonDecode(jsonEncode(guide.toJson())) as Map<String, dynamic>,
      ).cover?.url,
      'https://media.test/images/cards/v1/guide-x--01.webp',
    );
    final topic = Summary.fromJson({
      ...summaryJson(kind: 'topic', coverage: 'topic'),
      'authors': ['Seneca', 'NHS', 'Montaigne'],
      'source_count': 3,
    });
    expect(topic.byline, 'From 3 sources, including Seneca, NHS and more');
  });

  test('progress: resume where stopped, start over once finished', () {
    const p = SummaryProgress(started: true, position: 5);
    expect(p.resumeIndex(10), 5);
    expect(p.resumeIndex(3), 2);
    expect(
      const SummaryProgress(
        started: true,
        position: 5,
        finished: true,
      ).resumeIndex(10),
      0,
    );
    expect(const SummaryProgress().resumeIndex(10), 0);
    // This device can be further along than the copy the feed had.
    expect(
      bestProgress(
        const SummaryProgress(started: true, position: 1),
        const SummaryProgress(started: true, position: 2),
      )!.position,
      2,
    );
    expect(bestProgress(null, null), isNull);
  });

  testWidgets('a summary post sits in the swipe feed and opens part by part', (
    tester,
  ) async {
    final server = serverWithSummary();
    await pumpApp(tester, server, size: phone);
    await tester.fling(
      find.byKey(const ValueKey('swipe-feed')),
      const Offset(0, -300),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.text('The Example Book'), findsOneWidget);
    expect(find.text('FULL SUMMARY  ·  PERSONAL DEVELOPMENT'), findsOneWidget);
    expect(find.text('3 parts · 2 min'), findsOneWidget);
    // Summary posts are never marked seen as cards.
    await tester.tap(find.byKey(const ValueKey('summary-start')));
    await tester.pumpAndSettle();

    expect(find.text('Part idea 1'), findsOneWidget);
    expect(find.text('Part 1 of 3'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('summary-next')));
    await tester.pumpAndSettle();
    expect(find.text('Part idea 2'), findsOneWidget);

    // A sideways swipe turns the page too, and arrow keys.
    await tester.fling(pages, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Part idea 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Part idea 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('summary-next'))); // Finish
    await tester.pumpAndSettle();
    expect(find.text("You've finished The Example Book"), findsOneWidget);

    // Signed out: the place is kept on the device only.
    expect(server.called('PUT /v1/summaries/example-book/progress'), isEmpty);
  });

  testWidgets('it picks up where the reader stopped, and saves the place', (
    tester,
  ) async {
    final server = serverWithSummary(
      viewer: {'started': true, 'position': 1, 'finished': false},
    );
    final container = await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/summaries/example-book',
    );
    expect(find.text('Part idea 2'), findsOneWidget);
    expect(
      find.textContaining('Picking up where you left off'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('summary-next')));
    await tester.pumpAndSettle();
    final saved = server
        .called('PUT /v1/summaries/example-book/progress')
        .map((c) => c.body)
        .toList();
    expect(saved.last, {'position': 2, 'finished': true});
    expect(container.read(summaryPlacesProvider)['example-book']!.position, 2);
    // Moving past a part counts as reading it.
    expect(server.called('POST /v1/cards/example-book--02/view'), isNotEmpty);
  });

  testWidgets('Read it all shows every part on one page', (tester) async {
    final server = serverWithSummary();
    await pumpApp(tester, server, location: '/summaries/example-book?view=all');
    expect(find.byKey(const ValueKey('summary-all')), findsOneWidget);
    expect(find.text('Part idea 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text("You've finished The Example Book"),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('summary-all')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Part idea 3'), findsOneWidget);
  });

  testWidgets('wide screens show the summary post in the column', (
    tester,
  ) async {
    final server = serverWithSummary();
    await pumpApp(tester, server, size: const Size(1000, 2000));
    expect(
      find.byKey(const ValueKey('summary-post-example-book')),
      findsOneWidget,
    );
    expect(find.text('Idea p2'), findsOneWidget);
  });
}

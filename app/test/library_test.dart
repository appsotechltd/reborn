import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/library/card_collection.dart';
import 'package:reborn/src/features/library/library_controller.dart';
import 'package:reborn/src/features/library/library_screen.dart';
import 'package:reborn/src/features/listen/listen_audio.dart';
import 'package:reborn/src/features/listen/listen_controller.dart';
import 'package:reborn/src/features/social/author_screen.dart';
import 'package:reborn/src/features/source/source_screen.dart';

import 'fake_server.dart';
import 'fakes.dart';
import 'fixtures.dart';

const phone = Size(390, 844);

Map<String, dynamic> book(String id, {int cards = 3, int videos = 0}) => {
  'id': id,
  'title': 'Book $id',
  'authors': ['Author $id'],
  'kind': 'book',
  'licence': 'public-domain',
  'attribution': '',
  'topics': ['mindfulness'],
  'card_count': cards,
  'video_count': videos,
  'updated_at': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> author(String name, {int videos = 0}) => {
  'name': name,
  'sources': 2,
  'card_count': 9,
  'video_count': videos,
  'topics': ['mindfulness'],
  'followers': 1,
};

Map<String, dynamic> card(
  String id, {
  bool withVideo = false,
  bool withImage = false,
}) => cardJsonWith({
  'id': id,
  'title': 'Idea $id',
  'quote': null,
  'audio': {
    'url': '/media/audio/$id.mp3',
    'duration_s': 30,
    'voice': 'bf_emma',
    'voice_name': 'Emma',
  },
  if (withVideo)
    'explainer': {
      'kind': 'animated',
      'video_url': '/media/$id.mp4',
      'poster_url': '/media/$id.jpg',
      'duration_s': 42,
    },
  if (withImage)
    'image': {
      'url': 'https://media.example.com/$id.webp',
      'type': 'illustration',
      'caption': 'A picture',
    },
});

const sourceId = 'meditations-marcus-aurelius';

Map<String, dynamic> sourceDetail(List<Map<String, dynamic>> cards) => {
  'source': cardJson()['source'],
  'cards': cards,
  'follow': {'followers': 0, 'is_following': false},
};

void main() {
  group('Library', () {
    testWidgets('Books tab lists books with counts, a video badge and '
        'topics; a book opens its page', (tester) async {
      final server = FakeServer()
        ..on(
          'GET /v1/sources',
          (_) => {
            'sources': [book('a', videos: 2), book('b')],
            'next_cursor': null,
          },
        )
        ..on('GET /v1/sources/a', (_) => sourceDetail([card('x--01')]));
      await pumpApp(tester, server, size: phone, location: '/library');
      expect(find.text('Book a'), findsOneWidget);
      expect(find.text('Author a'), findsOneWidget);
      expect(find.text('2 videos'), findsOneWidget);
      // Book b has no videos: no badge.
      expect(find.text('0 videos'), findsNothing);
      expect(find.text('3 ideas'), findsNWidgets(2));
      expect(find.text('MINDFULNESS'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Book a'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceScreen), findsOneWidget);
    });

    testWidgets('Authors tab (and ?tab=authors) lists authors; one opens '
        'the author page', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/sources', (_) => {'sources': [], 'next_cursor': null})
        ..on(
          'GET /v1/authors',
          (_) => {
            'authors': [author('Seneca', videos: 1), author('Epictetus')],
            'next_cursor': null,
          },
        );
      await pumpApp(
        tester,
        server,
        size: phone,
        location: '/library?tab=authors',
      );
      expect(find.text('Seneca'), findsOneWidget);
      expect(find.text('2 books · 9 ideas'), findsNWidgets(2));
      expect(find.text('1 video'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-tab-books')));
      await tester.pumpAndSettle();
      expect(find.text('No books yet.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-tab-authors')));
      await tester.pumpAndSettle();
      server.on(
        'GET /v1/authors/Seneca',
        (_) => {
          'name': 'Seneca',
          'sources': [book('a')],
          'cards': [card('x--01')],
          'card_count': 1,
          'video_count': 0,
          'followers': 0,
          'is_following': false,
        },
      );
      await tester.tap(find.text('Seneca'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthorScreen), findsOneWidget);
      expect(find.text('Idea x--01'), findsOneWidget);
    });

    testWidgets('search is debounced and sent as q; topic chips filter', (
      tester,
    ) async {
      final server = FakeServer()
        ..on(
          'GET /v1/topics',
          (_) => {
            'topics': [
              {'slug': 'mindfulness', 'name': 'Mindfulness & Philosophy'},
              {'slug': 'health', 'name': 'Health & Wellness'},
            ],
          },
        )
        ..on('GET /v1/sources', (c) {
          final q = c.query['q'] ?? '';
          final topic = c.query['topic'];
          return {
            'sources': [
              if (q.isEmpty && topic == null) ...[book('a'), book('b')],
              if (q == 'med') book('med'),
              if (topic == 'mindfulness') book('h'),
            ],
            'next_cursor': null,
          };
        });
      await pumpApp(tester, server, size: phone, location: '/library');
      expect(find.text('Book a'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        'me',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        'med',
      );
      await tester.pump(kLibrarySearchDebounce);
      await tester.pumpAndSettle();
      expect(find.text('Book med'), findsOneWidget);
      expect(find.text('Book a'), findsNothing);
      // Only the settled text was searched.
      expect(server.called('GET /v1/sources').map((c) => c.query['q']), [
        null,
        'med',
      ]);

      await tester.tap(find.byKey(const ValueKey('library-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Book a'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-topic-mindfulness')));
      await tester.pumpAndSettle();
      expect(find.text('Book h'), findsOneWidget);
      expect(find.text('Book a'), findsNothing);
      expect(server.calls.last.query['topic'], 'mindfulness');

      await tester.tap(find.byKey(const ValueKey('library-topic-all')));
      await tester.pumpAndSettle();
      expect(find.text('Book a'), findsOneWidget);
    });

    testWidgets('pages load as the list nears its end', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/sources', (c) {
          final from = int.parse(c.query['cursor'] ?? '0');
          return {
            'sources': [
              for (var i = from; i < from + 20; i++)
                book(i.toString().padLeft(3, '0')),
            ],
            'next_cursor': from == 0 ? '20' : null,
          };
        });
      await pumpApp(tester, server, size: phone, location: '/library');
      expect(server.called('GET /v1/sources').length, 1);
      expect(find.text('Book 000'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Book 019'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('library-books')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final calls = server.called('GET /v1/sources').toList();
      expect(calls.length, 2);
      expect(calls.last.query['cursor'], '20');

      await tester.scrollUntilVisible(
        find.text('Book 039'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('library-books')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      // The last page had no cursor: nothing more loads.
      expect(server.called('GET /v1/sources').length, 2);
    });

    testWidgets('a failed page shows Try again', (tester) async {
      var fail = false;
      final server = FakeServer()
        ..on('GET /v1/authors', (c) {
          if (c.query['cursor'] != null && fail) {
            return Reply.error(500, 'internal', 'boom');
          }
          final from = int.parse(c.query['cursor'] ?? '0');
          return {
            'authors': [for (var i = from; i < from + 3; i++) author('A$i')],
            'next_cursor': from == 0 ? '3' : null,
          };
        });
      fail = true;
      await pumpApp(
        tester,
        server,
        size: phone,
        location: '/library?tab=authors',
      );
      expect(find.byKey(const ValueKey('library-more-retry')), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('library-more-retry')));
      await tester.pumpAndSettle();
      expect(find.text('A5'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-more-retry')), findsNothing);
    });

    testWidgets('expanded: a book opens beside the list', (tester) async {
      final server = FakeServer()
        ..on(
          'GET /v1/sources',
          (_) => {
            'sources': [book(sourceId)],
            'next_cursor': null,
          },
        )
        ..on('GET /v1/sources/$sourceId', (_) => sourceDetail([card('x--01')]))
        ..on('GET /v1/circles', (_) => {'circles': []});
      await pumpApp(
        tester,
        server,
        size: const Size(1280, 900),
        location: '/library',
      );
      expect(find.byKey(const ValueKey('empty-detail')), findsOneWidget);
      await tester.tap(find.text('Book $sourceId'));
      await tester.pumpAndSettle();
      // Not pushed: the list stays on the left.
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(SourceScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('two-pane')), findsOneWidget);
      expect(find.text('Idea x--01'), findsOneWidget);
    });

    testWidgets('Discover links to the Library', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/sources', (_) => {'sources': [], 'next_cursor': null});
      final container = await pumpApp(tester, server, size: phone);
      await push(tester, container, '/discover');
      await tester.tap(find.byKey(const ValueKey('discover-library')));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
    });
  });

  group('book and author pages', () {
    testWidgets('All / Videos switch filters the cards and shows counts', (
      tester,
    ) async {
      final server = FakeServer()
        ..on(
          'GET /v1/sources/$sourceId',
          (_) => sourceDetail([
            card('m--01'),
            card('m--02', withVideo: true),
            card('m--03'),
          ]),
        )
        ..on('GET /v1/circles', (_) => {'circles': []});
      await pumpApp(
        tester,
        server,
        size: phone,
        location: '/sources/$sourceId',
      );
      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('Videos 1'), findsOneWidget);
      expect(find.text('Idea m--01'), findsOneWidget);
      expect(find.text('Idea m--03'), findsOneWidget);

      await tester.tap(find.text('Videos 1'));
      await tester.pumpAndSettle();
      expect(find.text('Idea m--02'), findsOneWidget);
      expect(find.text('Idea m--01'), findsNothing);
      expect(find.text('Idea m--03'), findsNothing);

      await tester.tap(find.text('All 3'));
      await tester.pumpAndSettle();
      expect(find.text('Idea m--01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Images keeps the cards with a picture; Videos is hidden '
        'when none has a video', (tester) async {
      final server = FakeServer()
        ..on(
          'GET /v1/sources/$sourceId',
          (_) => sourceDetail([
            card('m--01', withImage: true),
            card('m--02'),
            card('m--03', withImage: true),
          ]),
        )
        ..on('GET /v1/circles', (_) => {'circles': []});
      final container = await pumpApp(
        tester,
        server,
        size: phone,
        location: '/sources/$sourceId',
      );
      expect(find.text('All 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('cards-filter-videos')), findsNothing);
      expect(find.text('Images 2'), findsOneWidget);

      await tester.tap(find.text('Images 2'));
      await tester.pumpAndSettle();
      expect(find.text('Idea m--01'), findsOneWidget);
      expect(find.text('Idea m--02'), findsNothing);
      expect(find.text('Idea m--03'), findsOneWidget);
      expect(
        container.read(cardsFilterProvider('source:$sourceId')),
        MediaFilter.images,
      );
      expect(tester.takeException(), isNull);
    });

    test('Listen keys name the list shown', () {
      expect(collectionListenKey('source:x', MediaFilter.all), 'source:x|all');
      expect(
        collectionListenKey('source:x', MediaFilter.videos),
        'source:x|videos',
      );
      expect(
        collectionListenKey('author:Ada', MediaFilter.images),
        'author:Ada|images',
      );
      final cards = [
        IdeaCard.fromJson(card('a', withVideo: true)),
        IdeaCard.fromJson(card('b', withImage: true)),
        IdeaCard.fromJson(card('c')),
      ];
      expect(visibleCards(cards, MediaFilter.videos).map((c) => c.id), ['a']);
      expect(visibleCards(cards, MediaFilter.images).map((c) => c.id), ['b']);
      expect(visibleCards(cards, MediaFilter.all), hasLength(3));
      // A filter none of the cards matches falls back to All.
      expect(collectionFilter([cards[2]], MediaFilter.videos), MediaFilter.all);
    });

    testWidgets('the switch is hidden when no card has a video', (
      tester,
    ) async {
      final server = FakeServer()
        ..on(
          'GET /v1/sources/$sourceId',
          (_) => sourceDetail([card('m--01'), card('m--02')]),
        )
        ..on('GET /v1/circles', (_) => {'circles': []});
      await pumpApp(
        tester,
        server,
        size: phone,
        location: '/sources/$sourceId',
      );
      expect(find.byKey(const ValueKey('cards-filter')), findsNothing);
      expect(find.text('Listen to this book'), findsOneWidget);
    });

    testWidgets('Listen to this book plays the shown cards as a fixed '
        'queue, marking them read as on the timeline', (tester) async {
      final audio = FakeListenAudio();
      final server = FakeServer()
        ..on(
          'GET /v1/sources/$sourceId',
          (_) => sourceDetail([
            card('m--01'),
            card('m--02', withVideo: true),
            card('m--03', withVideo: true),
          ]),
        )
        ..on('GET /v1/circles', (_) => {'circles': []})
        ..on('POST /v1/seen', (_) => const Reply.empty())
        ..on('POST /v1/cards/m--02/view', (_) => const Reply.empty())
        ..on('POST /v1/cards/m--03/view', (_) => const Reply.empty());
      final container = await pumpApp(
        tester,
        server,
        size: phone,
        prefs: signedInPrefs,
        location: '/sources/$sourceId',
        overrides: [listenAudioProvider.overrideWithValue(audio)],
      );
      final timelineCalls = server.called('GET /v1/timeline').length;
      // Videos only: the queue is the two video cards, in page order.
      await tester.tap(find.text('Videos 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('listen-collection')));
      await tester.pumpAndSettle();
      expect(find.text('Now listening'), findsOneWidget);
      final s = container.read(listenProvider);
      expect(s.queue.map((p) => p.card.id), ['m--02', 'm--03']);
      expect(s.single, isFalse);
      expect(audio.played, [resolveMediaUrl('/media/audio/m--02.mp3')]);

      // Heard to the end: read, then the next card of the book.
      audio.moveTo(const Duration(seconds: 30));
      audio.finish();
      await tester.pumpAndSettle();
      expect(server.called('POST /v1/cards/m--02/view').length, 1);
      expect(container.read(listenProvider).current!.card.id, 'm--03');

      // The end of the book is the end: no timeline paging.
      audio.moveTo(const Duration(seconds: 30));
      audio.finish();
      await tester.pumpAndSettle();
      expect(container.read(listenProvider).finished, isTrue);
      expect(server.called('GET /v1/timeline').length, timelineCalls);
      expect(server.called('POST /v1/cards/m--03/view').length, 1);
    });

    testWidgets('author page lists books then every card, with Listen to '
        'this author', (tester) async {
      final audio = FakeListenAudio();
      final server = FakeServer()
        ..on(
          'GET /v1/authors/Marcus%20Aurelius',
          (_) => {
            'name': 'Marcus Aurelius',
            'sources': [book(sourceId, cards: 2, videos: 1)],
            'cards': [card('m--01'), card('m--02', withVideo: true)],
            'card_count': 2,
            'video_count': 1,
            'followers': 3,
            'is_following': false,
          },
        );
      final container = await pumpApp(
        tester,
        server,
        size: phone,
        location: '/authors/Marcus%20Aurelius',
        overrides: [listenAudioProvider.overrideWithValue(audio)],
      );
      expect(find.text('Book $sourceId'), findsOneWidget);
      expect(find.text('All 2 ideas by Marcus Aurelius'), findsOneWidget);
      expect(find.text('Idea m--01'), findsOneWidget);
      expect(find.text('Videos 1'), findsOneWidget);

      await tester.tap(find.text('Videos 1'));
      await tester.pumpAndSettle();
      expect(find.text('Idea m--01'), findsNothing);
      expect(find.text('Idea m--02'), findsOneWidget);

      await tester.tap(find.text('All 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listen to this author'));
      await tester.pumpAndSettle();
      expect(container.read(listenProvider).queue.map((p) => p.card.id), [
        'm--01',
        'm--02',
      ]);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';

import 'fixtures.dart';

void main() {
  group('Explainer', () {
    test('parses, round-trips and is absent by default', () {
      expect(sampleCard().explainer, isNull);
      final card = sampleCard({
        'explainer': {
          'kind': 'animated',
          'video_url': '/media/explainers/x--01.mp4',
          'poster_url': '/media/explainers/x--01.jpg',
          'duration_s': 52,
          'width': 720,
          'height': 1280,
          'narrated': true,
        },
      });
      final e = card.explainer!;
      expect(e.videoUrl, '/media/explainers/x--01.mp4');
      expect(e.durationS, 52.0);
      expect(e.aspectRatio, closeTo(0.5625, 1e-9));
      expect(e.narrated, isTrue);
      final again = IdeaCard.fromJson(card.toJson()).explainer!;
      expect(again.posterUrl, e.posterUrl);
      expect(sampleCard().toJson().containsKey('explainer'), isFalse);
    });

    test('media URLs resolve against the API base unless absolute', () {
      expect(
        resolveMediaUrl('/media/explainers/a.mp4', 'https://api.example.org/'),
        'https://api.example.org/media/explainers/a.mp4',
      );
      expect(
        resolveMediaUrl(
          'https://cdn.example.org/a.mp4',
          'https://api.example.org',
        ),
        'https://cdn.example.org/a.mp4',
      );
    });
  });

  group('IdeaCard.fromJson (API.md example)', () {
    final card = IdeaCard.fromJson(cardJson());

    test('parses every field', () {
      expect(card.id, 'meditations-marcus-aurelius--01');
      expect(card.title, 'Expect difficult people before the day starts');
      expect(card.body, 'Each morning, Marcus reminded himself...');
      expect(card.quote, 'Begin the morning by saying to thyself...');
      expect(
        card.applyIt,
        'Before your next meeting, name one way it could go badly...',
      );
      expect(card.topic, 'mindfulness');
      expect(card.tags, ['stoicism']);
      expect(card.locator, 'Book II, 1');
      expect(card.health, isFalse);
      expect(card.disclaimer, isNull);
      expect(
        card.credit,
        'Source: Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain',
      );
    });

    test('parses quiz', () {
      expect(card.quiz, isNotNull);
      expect(card.quiz!.question, '...');
      expect(card.quiz!.options, ['...', '...']);
      expect(card.quiz!.answer, 1);
      expect(card.quiz!.explanation, '...');
    });

    test('parses source', () {
      final s = card.source;
      expect(s.id, 'meditations-marcus-aurelius');
      expect(s.title, 'Meditations');
      expect(s.authors, ['Marcus Aurelius']);
      expect(s.kind, 'book');
      expect(s.url, 'https://www.gutenberg.org/ebooks/2680');
      expect(s.licence, 'public-domain');
      expect(s.licenceUrl, 'https://www.gutenberg.org/policy/license.html');
      expect(s.attribution, startsWith('Marcus Aurelius, Meditations'));
    });

    test('toJson round-trips with snake_case keys', () {
      final json =
          jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>;
      expect(json['apply_it'], card.applyIt);
      expect(json['source']['licence_url'], card.source.licenceUrl);
      final again = IdeaCard.fromJson(json);
      expect(again.toJson(), card.toJson());
    });

    test('optional fields may be absent or null', () {
      final json = cardJson()
        ..remove('quote')
        ..remove('locator')
        ..['quiz'] = null
        ..remove('tags');
      final c = IdeaCard.fromJson(json);
      expect(c.quote, isNull);
      expect(c.locator, isNull);
      expect(c.quiz, isNull);
      expect(c.tags, isEmpty);
    });

    test('health card carries its disclaimer', () {
      final c = healthCard();
      expect(c.health, isTrue);
      expect(c.disclaimer, healthDisclaimer);
    });
  });

  test('User, Stash, FeedPage, ReviewDue, Contribution parse', () {
    final user = User.fromJson(const {
      'id': 'u1',
      'email': 'a@b.com',
      'display_name': 'Ada',
      'role': 'moderator',
      'topics': ['psychology'],
    });
    expect(user.displayName, 'Ada');
    expect(user.isModerator, isTrue);
    expect(user.topics, ['psychology']);

    final stash = Stash.fromJson(const {
      'id': 's1',
      'name': 'Morning reads',
      'description': '',
      'card_count': 3,
      'created_at': '2026-10-10T12:00:00Z',
    });
    expect(stash.cardCount, 3);
    expect(stash.createdAt, DateTime.utc(2026, 10, 10, 12));

    final page = FeedPage.fromJson({
      'cards': [cardJson()],
      'next_cursor': null,
    });
    expect(page.cards.single.id, 'meditations-marcus-aurelius--01');
    expect(page.nextCursor, isNull);

    final due = ReviewDue.fromJson({
      'items': [
        {
          'card': cardJson(),
          'due_at': '2026-10-10T12:00:00Z',
          'reps': 2,
          'interval_days': 3,
        },
      ],
      'due_count': 7,
    });
    expect(due.dueCount, 7);
    expect(due.items.single.reps, 2);
    expect(due.items.single.intervalDays, 3);

    final c = Contribution.fromJson(const {
      'id': 'c1',
      'status': 'pending',
      'source': {
        'title': 'Deep Work',
        'authors': ['Cal Newport'],
        'url': 'https://example.com',
        'kind': 'book',
      },
      'topic': 'productivity',
      'title': 't',
      'body': 'b',
      'apply_it': 'a',
      'tags': [],
      'quiz': null,
      'moderator_note': null,
      'card_id': null,
      'created_at': '2026-10-10T12:00:00Z',
    });
    expect(c.status, 'pending');
    expect(c.source.authors, ['Cal Newport']);
    expect(c.cardId, isNull);
  });

  test('ContributionDraft.toJson matches POST /v1/contributions', () {
    final json = const ContributionDraft(
      source: ContributionSource(
        title: 'Deep Work',
        authors: ['Cal Newport'],
        url: 'https://x.org',
        kind: 'book',
      ),
      topic: 'productivity',
      title: 'Title',
      body: 'Body',
      applyIt: 'Do it',
    ).toJson();
    expect(
      json.keys,
      containsAll(['source', 'topic', 'title', 'body', 'apply_it']),
    );
    expect(json.containsKey('quiz'), isFalse);
    expect(json['source'], {
      'title': 'Deep Work',
      'authors': ['Cal Newport'],
      'url': 'https://x.org',
      'kind': 'book',
    });
  });

  test('wordCount', () {
    expect(wordCount(''), 0);
    expect(wordCount('  one  two\nthree\n\nfour '), 4);
  });
}

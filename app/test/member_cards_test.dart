import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/member_models.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/features/card/illustrated_video_player.dart';
import 'package:reborn/src/features/gifts/gift_store.dart';
import 'package:reborn/src/features/writers/writer_pass_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gift_store.dart';
import 'fake_server.dart';
import 'fixtures.dart';

/// A member card as the API sends it (docs/API.md, "Member cards").
Map<String, dynamic> memberCardJson([Map<String, dynamic> extra = const {}]) =>
    {
      'id': 'm-7f3a9c21',
      'title': 'Walk before you scroll',
      'body': 'Ten minutes outside before the phone sets the tone.',
      'apply_it': '',
      'topic': 'mindfulness',
      'tags': <String>[],
      'health': false,
      'source': {
        'id': 'reborn-members',
        'title': 'Reborn members',
        'authors': ['Ada'],
        'kind': 'members',
      },
      'credit': 'Written by Ada on Reborn',
      'author': {'id': 'u1', 'handle': 'ada', 'display_name': 'Ada'},
      'category': {'id': 'c1', 'name': 'Mornings'},
      'visibility': 'subscribers',
      'created_at': '2026-10-12T08:00:00Z',
      'video': {
        'kind': 'illustrated',
        'scenes': [
          {
            'url': 'https://media.example.com/a.webp',
            'width': 1024,
            'height': 1536,
          },
          {
            'url': 'https://media.example.com/b.webp',
            'width': 1024,
            'height': 1536,
          },
        ],
        'audio_url': 'https://media.example.com/a.mp3',
        'voice': 'bf_emma',
        'duration_s': 31.5,
      },
      ...extra,
    };

void main() {
  group('member cards', () {
    test('parse author, category, visibility, date and video', () {
      final c = IdeaCard.fromJson(memberCardJson());
      expect(c.isMemberCard, isTrue);
      expect(c.author!.handle, 'ada');
      expect(c.author!.name, 'Ada');
      expect(c.category!.name, 'Mornings');
      expect(c.visibility, 'subscribers');
      expect(c.createdAt, DateTime.utc(2026, 10, 12, 8));
      final v = c.video!;
      expect(v.scenes, hasLength(2));
      expect(v.scenes.first.height, 1536);
      expect(v.audioUrl, 'https://media.example.com/a.mp3');
      expect(v.duration, const Duration(milliseconds: 31500));
      // Round-trips through the offline cache's JSON.
      final again = IdeaCard.fromJson(c.toJson());
      expect(again.author!.displayName, 'Ada');
      expect(again.video!.scenes.last.url, 'https://media.example.com/b.webp');
      expect(again.visibility, 'subscribers');
      // No "Apply it" on this card, and it's read as the writer's.
      expect(c.spokenText, isNot(contains('Apply it')));
      expect(c.spokenText, endsWith('By Ada.'));
    });

    test('library cards keep working without the member fields', () {
      final c = sampleCard();
      expect(c.isMemberCard, isFalse);
      expect(c.author, isNull);
      expect(c.category, isNull);
      expect(c.visibility, isNull);
      expect(c.video, isNull);
      final json = c.toJson();
      expect(json.containsKey('author'), isFalse);
      expect(json.containsKey('video'), isFalse);
      expect(c.spokenText, contains('Apply it.'));
    });

    test('a video without narration, or odd shapes, are ignored', () {
      final c = IdeaCard.fromJson(
        memberCardJson({
          'video': {'scenes': <Object>[], 'audio_url': ''},
          'author': 'not a map',
          'category': null,
        }),
      );
      expect(c.video, isNull);
      expect(c.author, isNull);
      expect(c.category, isNull);
    });

    test('timeline reason for a writer you follow', () {
      const r = PostReason(kind: 'writer', label: 'Ada');
      expect(r.text, 'From Ada, who you follow');
    });

    test('audience labels', () {
      expect(kAudiences.map(audienceLabel), [
        'Everyone',
        'Followers',
        'Subscribers',
        'Only me',
      ]);
      expect(audienceLabel('hidden'), 'Hidden');
    });
  });

  group('studio prices', () {
    test('audio is a unit per started 50 words, at least one', () {
      String words(int n) => List.filled(n, 'word').join(' ');
      // The title counts too: "T." is one word.
      expect(studioAudioUnits('T', '', ''), 1);
      expect(studioAudioUnits('T', words(49), ''), 1);
      expect(studioAudioUnits('T', words(50), ''), 2);
      // "Apply it." adds two words when there is an apply-it line.
      expect(studioAudioUnits('T', words(47), 'go'), 2);
      expect(studioAudioUnits('T', words(46), 'go'), 1);
    });

    test('video is 1 + an illustration per scene + the audio', () {
      final s = StudioStatus.fromJson({
        'available': true,
        'premium': true,
        'video_scenes': 4,
        'monthly_units': 250,
        'rates': [
          {'kind': 'sketch', 'units': 2, 'per': 'sketch'},
          {'kind': 'illustration', 'units': 4, 'per': 'illustration'},
          {'kind': 'picture', 'units': 12, 'per': 'photo-like picture'},
          {'kind': 'audio', 'units': 3, 'per': 'minute of audio'},
          {'kind': 'video', 'units': 20, 'per': 'illustrated video'},
        ],
        'voices': [
          {'id': 'af_heart', 'name': 'Heart'},
        ],
        'wallet': {
          'monthly_units': 250,
          'allowance_used': 10,
          'allowance_left': 240,
          'topup_units': 0,
          'remaining': 240,
          'resets_at': '2026-11-01T00:00:00Z',
        },
      });
      expect(s.imageUnits(StudioStyle.sketch), 2);
      expect(s.imageUnits(StudioStyle.picture), 12);
      expect(s.audioUnits('Title', 'one two three', ''), 1);
      expect(s.videoUnits('Title', 'one two three', ''), 1 + 16 + 1);
      expect(s.wallet!.remaining, 240);
      expect(s.voices.single.name, 'Heart');
      expect(
        s.allowanceLine,
        '12 videos, 62 illustrations or 83 one-minute audios',
      );
    });

    test('defaults hold when the server sends no rates', () {
      const s = StudioStatus();
      expect(s.imageUnits(StudioStyle.illustration), 4);
      expect(s.videoUnits('T', 'x', ''), 18);
    });
  });

  group('illustrated video timing', () {
    const total = Duration(seconds: 40);
    SceneFrame at(int ms) => sceneAt(4, total, Duration(milliseconds: ms));

    test('each scene gets an equal share', () {
      expect(at(0).index, 0);
      expect(at(9000).index, 0);
      expect(at(10000).index, 1);
      expect(at(25000).index, 2);
      expect(at(39999).index, 3);
      expect(at(50000).index, 3); // past the end: the last scene
      expect(at(5000).progress, closeTo(0.5, 1e-9));
    });

    test('the next scene fades in over the last 0.8 s', () {
      expect(at(9000).fade, 0);
      expect(at(9600).fade, closeTo(0.5, 1e-9));
      expect(at(10000).fade, 0); // the next scene now shows
      expect(at(39900).fade, 0); // nothing after the last scene
    });

    test('no scenes or no length shows the first scene still', () {
      final f = sceneAt(0, total, const Duration(seconds: 3));
      expect((f.index, f.progress, f.fade), (0, 0.0, 0.0));
      final g = sceneAt(4, Duration.zero, const Duration(seconds: 3));
      expect(g.index, 0);
    });
  });

  group('writers', () {
    test('offer, plan and earnings parse', () {
      final offer = WriterOffer.fromJson({
        'plan': {'pitch': 'Weekly notes', 'subscribers': 3},
        'tier': {
          'id': 'month_499',
          'amount_cents': 499,
          'currency': 'usd',
          'product_id': 'reborn.writer.month499',
        },
        'locked_cards': 5,
        'subscription': {
          'writer': {'id': 'u1', 'handle': 'ada', 'display_name': 'Ada'},
          'tier': 'month_499',
          'provider': 'stripe',
          'renews': true,
          'expires_at': '2026-11-14T00:00:00Z',
          'active': true,
        },
        'providers': {'stripe': true, 'apple': false, 'google': true},
      });
      expect(offer.sells, isTrue);
      expect(offer.tier!.displayPrice, r'$4.99');
      expect(offer.lockedCards, 5);
      expect(offer.subscribed, isTrue);
      expect(offer.subscription!.renews, isTrue);
      expect(offer.enabled('google'), isTrue);
      expect(offer.enabled('apple'), isFalse);

      final none = WriterOffer.fromJson({
        'plan': null,
        'tier': null,
        'locked_cards': 0,
        'subscription': null,
      });
      expect(none.sells, isFalse);

      final plan = MyWriterPlan.fromJson({'plan': null, 'tiers': <Object>[]});
      expect(plan.tiers.map((t) => t.productId), [
        'reborn.writer.month199',
        'reborn.writer.month499',
        'reborn.writer.month999',
      ]);

      final e = Earnings.fromJson({
        'earnings': {
          'total_cents': 1234,
          'this_month_cents': 349,
          'gifts': 2,
          'subscribers': 1,
          'currency': 'usd',
          'recent': [
            {
              'kind': 'gift',
              'post_id': 'm-1',
              'post_title': 'Walk first',
              'tier': 'lamp',
              'amount_cents': 499,
              'author_cents': 349,
              'currency': 'usd',
              'from': {'id': 'u2', 'handle': 'bob', 'display_name': 'Bob'},
              'paid_at': '2026-10-12T08:00:00Z',
            },
          ],
        },
        'commission_percent': 30,
        'store_fee_percent': 15,
      });
      expect(moneyLabel(e.totalCents, e.currency), r'$12.34');
      expect(e.recent.single.from!.name, 'Bob');
      expect(e.commissionPercent, 30);
    });

    test(
      'a pass is bought in the store, sent to the server, then consumed',
      () async {
        final server = FakeServer()
          ..on(
            'POST /v1/users/ada/subscribe/google',
            (_) => Reply({
              'writer': {'id': 'u1', 'handle': 'ada', 'display_name': 'Ada'},
              'tier': 'month_499',
              'provider': 'google',
              'renews': false,
              'expires_at': '2026-11-14T00:00:00Z',
              'active': true,
            }, 201),
          );
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = FakeGiftStore(GiftPlatform.google);
        final subscribed = <String>[];
        final service = WriterPassService(
          store: store,
          repo: RebornRepository(
            ApiClient(httpClient: server.client, token: () => 't'),
            OfflineCache(prefs),
          ),
          prefs: prefs,
          onSubscribed: subscribed.add,
        );
        final sub = await service.subscribe('ada', kWriterTiers[1]);
        expect(sub.active, isTrue);
        expect(store.bought, ['reborn.writer.month499']);
        expect(
          server.called('POST /v1/users/ada/subscribe/google').single.body,
          {
            'product_id': 'reborn.writer.month499',
            'purchase_token': 'play-token',
          },
        );
        expect(store.finished, ['reborn.writer.month499']);
        expect(subscribed, ['ada']);
        expect(
          prefs.getString(
            '${WriterPassService.pendingPrefix}reborn.writer.month499',
          ),
          isNull,
        );
        service.dispose();
      },
    );
  });

  group('screens', () {
    Map<String, dynamic> bobCard() => memberCardJson({
      'id': 'm-1',
      'author': {'id': 'u2', 'handle': 'bob', 'display_name': 'Bob'},
      'visibility': 'everyone',
      'video': null,
    });

    testWidgets('a member card reads "by" its writer and can be reported', (
      tester,
    ) async {
      final server = FakeServer()
        ..on('GET /v1/posts/m-1', (_) => postJson(bobCard()))
        ..on('POST /v1/cards/m-1/view', (_) => const Reply.empty())
        ..on('POST /v1/posts/m-1/report', (_) => const Reply.empty());
      await pumpApp(
        tester,
        server,
        prefs: signedInPrefs,
        location: '/cards/m-1',
      );
      expect(find.text('by Bob'), findsOneWidget);
      expect(find.text('Reborn members'), findsNothing);
      expect(find.byKey(const ValueKey('post-gift')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('post-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'spam');
      await tester.tap(find.byKey(const ValueKey('report-send')));
      await tester.pumpAndSettle();
      expect(server.called('POST /v1/posts/m-1/report').single.body, {
        'reason': 'spam',
      });
      expect(find.text("Thanks, we'll take a look"), findsOneWidget);
    });

    testWidgets('my own card has no gift button and no report menu', (
      tester,
    ) async {
      final mine = memberCardJson({'id': 'm-2', 'video': null});
      final server = FakeServer()
        ..on('GET /v1/posts/m-2', (_) => postJson(mine))
        ..on('POST /v1/cards/m-2/view', (_) => const Reply.empty());
      await pumpApp(
        tester,
        server,
        prefs: signedInPrefs,
        location: '/cards/m-2',
      );
      expect(find.text('by Ada'), findsOneWidget);
      expect(find.byKey(const ValueKey('post-gift')), findsNothing);
      expect(find.byKey(const ValueKey('post-menu')), findsNothing);
    });

    testWidgets('write a card, then the studio prices each action', (
      tester,
    ) async {
      final saved = memberCardJson({
        'id': 'm-3',
        'title': 'Walk first',
        'body': 'Ten minutes outside.',
        'visibility': 'everyone',
        'category': null,
        'video': null,
      });
      final server = FakeServer()
        ..on(
          'GET /v1/topics',
          (_) => {
            'topics': [
              {'slug': 'mindfulness', 'name': 'Mindfulness', 'card_count': 1},
            ],
          },
        )
        ..on('GET /v1/me/categories', (_) => {'categories': <Object>[]})
        ..on('POST /v1/me/cards', (_) => Reply(saved, 201))
        ..on('GET /v1/me/cards/m-3', (_) => saved)
        ..on(
          'GET /v1/me/cards',
          (_) => {
            'cards': [saved],
            'next_cursor': null,
          },
        )
        ..on(
          'GET /v1/studio',
          (_) => {
            'available': true,
            'premium': true,
            'video_scenes': 4,
            'monthly_units': 250,
            'rates': <Object>[],
            'voices': [
              {'id': 'af_heart', 'name': 'Heart'},
            ],
            'wallet': {
              'monthly_units': 250,
              'allowance_used': 0,
              'allowance_left': 250,
              'topup_units': 0,
              'remaining': 250,
            },
          },
        );
      await pumpApp(
        tester,
        server,
        prefs: signedInPrefs,
        location: '/me/cards/new',
      );
      await tester.enterText(
        find.byKey(const ValueKey('card-title-field')),
        'Walk first',
      );
      await tester.enterText(
        find.byKey(const ValueKey('card-body-field')),
        'Ten minutes outside.',
      );
      await tester.tap(find.byKey(const ValueKey('card-topic-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mindfulness').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-followers')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('save-card')));
      await tester.tap(find.byKey(const ValueKey('save-card')));
      await tester.pumpAndSettle();
      expect(server.called('POST /v1/me/cards').single.body, {
        'title': 'Walk first',
        'body': 'Ten minutes outside.',
        'apply_it': '',
        'topic': 'mindfulness',
        'audience': 'followers',
      });
      expect(find.text('Edit card'), findsOneWidget);
      expect(find.text('250 units left this month'), findsOneWidget);
      expect(find.text('Make image · 4 units'), findsOneWidget);
      expect(find.text('Make audio · 1 unit'), findsOneWidget);
      expect(find.text('Make video · 18 units'), findsOneWidget);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';

import 'fixtures.dart';

void main() {
  late List<String> calls;
  late Object? Function(http.Request req) respond;

  ApiClient api() => ApiClient(
    baseUrl: 'http://api.test',
    token: () => 't',
    httpClient: MockClient((req) async {
      calls.add(
        '${req.method} ${req.url.path}'
        '${req.url.hasQuery ? '?${req.url.query}' : ''}'
        '${req.body.isEmpty ? '' : ' ${req.body}'}',
      );
      final out = respond(req);
      if (out is http.Response) return out;
      if (out == null) return http.Response('', 204);
      return http.Response(
        jsonEncode(out),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() {
    calls = [];
    respond = (_) => null;
  });

  test('timeline sends topics and cursor and parses posts', () async {
    respond = (_) => {
      'posts': [
        postJson(
          cardJson(),
          reason: {'kind': 'source', 'label': 'Meditations'},
        ),
      ],
      'next_cursor': '1760086800-20',
    };
    final page = await api().timeline(
      topics: ['health', 'money'],
      cursor: 'c1',
    );
    expect(
      calls.single,
      'GET /v1/timeline?topics=health%2Cmoney&cursor=c1&limit=20',
    );
    expect(page.posts.single.reason!.text, 'From Meditations');
    expect(page.nextCursor, '1760086800-20');
  });

  test('seen, reactions, favourites and share', () async {
    final a = api();
    await a.markSeen(['p1', 'p2']);
    await a.setReaction('p1', Reaction.insightful);
    await a.setReaction('p1', null);
    await a.setFavorite('p1', true);
    await a.setFavorite('p1', false);
    await a.share('p1', 'native');
    expect(calls, [
      'POST /v1/seen {"post_ids":["p1","p2"]}',
      'PUT /v1/posts/p1/reaction {"kind":"insightful"}',
      'DELETE /v1/posts/p1/reaction',
      'PUT /v1/posts/p1/favorite',
      'DELETE /v1/posts/p1/favorite',
      'POST /v1/posts/p1/share {"channel":"native"}',
    ]);
  });

  test('comments: list, reply, delete, report', () async {
    respond = (req) => switch ('${req.method} ${req.url.path}') {
      'GET /v1/posts/p1/comments' => {
        'comments': [
          {
            'id': 'c1',
            'post_id': 'p1',
            'parent_id': null,
            'body': 'Nice',
            'author': {'id': 'u', 'handle': 'ada', 'display_name': 'Ada'},
            'created_at': '2026-10-10T09:00:00Z',
          },
        ],
        'next_cursor': null,
      },
      'POST /v1/posts/p1/comments' => {
        'id': 'c2',
        'post_id': 'p1',
        'parent_id': 'c1',
        'body': 'Agreed',
        'author': {'id': 'u', 'handle': 'ada', 'display_name': 'Ada'},
        'created_at': '2026-10-10T09:01:00Z',
      },
      _ => null,
    };
    final a = api();
    final page = await a.comments('p1');
    expect(page.comments.single.author.handle, 'ada');
    final reply = await a.addComment('p1', 'Agreed', parentId: 'c1');
    expect(reply.parentId, 'c1');
    await a.deleteComment('c2');
    await a.reportComment('c1', reason: 'spam');
    expect(calls.skip(1), [
      'POST /v1/posts/p1/comments {"body":"Agreed","parent_id":"c1"}',
      'DELETE /v1/comments/c2',
      'POST /v1/comments/c1/report {"reason":"spam"}',
    ]);
  });

  test('follows escape author names; profile and favourites', () async {
    respond = (req) => req.url.path.startsWith('/v1/follows')
        ? {'followers': 3, 'is_following': true}
        : null;
    final f = await api().setFollow(FollowKind.author, 'Marcus Aurelius', true);
    expect(f.isFollowing, isTrue);
    expect(f.followers, 3);
    await api().setFollow(FollowKind.source, 'meditations', false);
    expect(calls, [
      'PUT /v1/follows/author/Marcus%20Aurelius',
      'DELETE /v1/follows/source/meditations',
    ]);
  });

  test('account: handle/bio, delete, forgot password', () async {
    respond = (req) => switch ('${req.method} ${req.url.path}') {
      'PATCH /v1/me' => {
        'id': 'u1',
        'email': 'a@b.com',
        'handle': 'ada_l',
        'display_name': 'Ada',
        'bio': 'Hello',
        'role': 'member',
        'topics': [],
      },
      'POST /v1/auth/forgot' => http.Response('', 202),
      _ => null,
    };
    final a = api();
    final u = await a.updateMe(handle: 'ada_l', bio: 'Hello');
    expect(u.handle, 'ada_l');
    await a.forgotPassword('a@b.com');
    await a.deleteMe();
    expect(calls, [
      'PATCH /v1/me {"handle":"ada_l","bio":"Hello"}',
      'POST /v1/auth/forgot {"email":"a@b.com"}',
      'DELETE /v1/me',
    ]);
  });

  test('409 handle_taken is recognisable', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'error': {'code': 'handle_taken', 'message': 'that handle is taken'},
      }),
      409,
    );
    await expectLater(
      api().updateMe(handle: 'bob'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.code, 'code', 'handle_taken'),
      ),
    );
  });

  test('gifts: tiers, Apple JWS and Google token', () async {
    final gift = {
      'id': 'g1',
      'post_id': 'p1',
      'tier': 'lamp',
      'amount_cents': 499,
      'currency': 'usd',
      'provider': 'apple',
      'status': 'paid',
      'created_at': '2026-10-10T09:00:00Z',
      'paid_at': '2026-10-10T09:00:00Z',
    };
    respond = (req) => req.url.path == '/v1/gifts/tiers'
        ? {
            'tiers': [
              {
                'id': 'spark',
                'name': 'Spark',
                'amount_cents': 199,
                'currency': 'usd',
                'product_id': 'reborn.gift.spark',
              },
            ],
            'providers': {'stripe': true, 'apple': false, 'google': true},
          }
        : gift;
    final a = api();
    final tiers = await a.giftTiers();
    expect(tiers.enabled('google'), isTrue);
    expect((await a.giftApple('p1', 'jws.payload.sig')).status, 'paid');
    await a.giftGoogle('p1', 'reborn.gift.lamp', 'tok123');
    expect(calls.skip(1), [
      'POST /v1/posts/p1/gifts/apple {"signed_transaction":"jws.payload.sig"}',
      'POST /v1/posts/p1/gifts/google '
          '{"product_id":"reborn.gift.lamp","purchase_token":"tok123"}',
    ]);
  });

  test('source detail carries follow state', () {
    final d = SourceDetail.fromJson({
      'source': cardJson()['source'],
      'cards': [cardJson()],
      'follow': {'followers': 7, 'is_following': true},
    });
    expect(d.follow.followers, 7);
    expect(d.follow.isFollowing, isTrue);
    // Older cached copies without `follow` still parse.
    expect(
      SourceDetail.fromJson({'source': cardJson()['source'], 'cards': []})
          .follow
          .isFollowing,
      isFalse,
    );
  });
}

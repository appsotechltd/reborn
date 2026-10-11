import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/post/share.dart';
import 'package:reborn/src/features/timeline/timeline_controller.dart';
import 'package:reborn/src/widgets/common.dart';

import 'fixtures.dart';

void main() {
  group('Post', () {
    test('parses the API example', () {
      final p = Post.fromJson(
        postJson(
          cardJson(),
          reactions: {'love': 3, 'insightful': 1},
          comments: 2,
          favorites: 5,
          shares: 1,
          viewer: {'reaction': 'love', 'favorited': true, 'seen': false},
          reason: {'kind': 'author', 'label': 'Marcus Aurelius'},
        ),
      );
      expect(p.id, 'meditations-marcus-aurelius--01');
      expect(p.card.title, sampleCard().title);
      expect(p.publishedAt, DateTime.utc(2026, 10, 10, 9));
      expect(p.stats.reactions, {'love': 3, 'insightful': 1});
      expect(p.stats.totalReactions, 4);
      expect(p.stats.comments, 2);
      expect(p.myReaction, Reaction.love);
      expect(p.favorited, isTrue);
      expect(p.reason!.text, 'Because you follow Marcus Aurelius');
    });

    test('signed out: no viewer, nothing favourited', () {
      final p = Post.fromJson(postJson(cardJson()));
      expect(p.viewer, isNull);
      expect(p.myReaction, isNull);
      expect(p.favorited, isFalse);
      expect(p.reason, isNull);
    });

    test('withReaction moves, adds and clears counts', () {
      var p = samplePost(
        reactions: {'love': 3},
        viewer: {'reaction': 'love', 'favorited': false, 'seen': true},
      );
      p = p.withReaction(Reaction.insightful);
      expect(p.stats.reactions, {'love': 2, 'insightful': 1});
      expect(p.myReaction, Reaction.insightful);
      expect(p.viewer!.seen, isTrue);
      p = p.withReaction(null);
      expect(p.stats.reactions, {'love': 2});
      expect(p.myReaction, isNull);
    });

    test('withFavorite adjusts the count once', () {
      final p = samplePost(favorites: 1).withFavorite(true);
      expect(p.favorited, isTrue);
      expect(p.stats.favorites, 2);
      expect(p.withFavorite(true).stats.favorites, 2);
      expect(p.withFavorite(false).stats.favorites, 1);
    });

    test('reason lines', () {
      String t(String kind, String label) =>
          PostReason(kind: kind, label: label).text;
      expect(t('source', 'Meditations'), 'From Meditations');
      expect(
        t('author', 'Marcus Aurelius'),
        'Because you follow Marcus Aurelius',
      );
      expect(t('favorite', 'Bob'), 'Bob favourited this');
      expect(
        t('topic', 'Mindfulness & Philosophy'),
        'In Mindfulness & Philosophy, one of your topics',
      );
      expect(t('new', ''), 'New on Reborn');
    });
  });

  test('caughtUpIndex finds where unseen posts end', () {
    Post p(String id, bool seen) => samplePost(
      card: {'id': id},
      viewer: {'reaction': null, 'favorited': false, 'seen': seen},
    );
    expect(caughtUpIndex([p('a', false), p('b', false), p('c', true)]), 2);
    expect(caughtUpIndex([p('a', true), p('b', true)]), 0);
    expect(caughtUpIndex([p('a', false)]), isNull);
    expect(caughtUpIndex([samplePost()]), isNull); // signed out
  });

  test('threadComments nests replies one level under their parent', () {
    Comment c(String id, [String? parent]) => Comment.fromJson({
      'id': id,
      'post_id': 'p',
      'parent_id': parent,
      'body': id,
      'author': {'id': 'u', 'handle': 'ada', 'display_name': 'Ada'},
      'created_at': '2026-10-10T09:00:00Z',
    });
    final threads = threadComments([
      c('1'),
      c('2'),
      c('1a', '1'),
      c('2a', '2'),
      c('1b', '1'),
      c('orphan', 'missing'),
    ]);
    expect(threads.map((t) => t.comment.id), ['1', '2', 'orphan']);
    expect(threads[0].replies.map((r) => r.id), ['1a', '1b']);
    expect(threads[1].replies.map((r) => r.id), ['2a']);
  });

  test('profile, author page, follows and user handle/bio', () {
    final p = Profile.fromJson({
      'id': 'u2',
      'handle': 'bob',
      'display_name': 'Bob',
      'bio': 'Reads',
      'followers': 2,
      'following': 5,
      'favorites': 12,
      'is_following': true,
      'is_me': false,
    });
    expect(p.handle, 'bob');
    expect(p.isFollowing, isTrue);
    expect(p.favorites, 12);

    final a = AuthorPage.fromJson({
      'name': 'Marcus Aurelius',
      'sources': [
        {'id': 'm', 'title': 'Meditations', 'card_count': 3, 'kind': 'book'},
      ],
      'followers': 4,
      'is_following': false,
    });
    expect(a.sources.single.title, 'Meditations');
    expect(a.follow.followers, 4);

    final u = User.fromJson({
      'id': 'u1',
      'email': 'a@b.com',
      'handle': 'ada',
      'display_name': 'Ada',
      'bio': 'Hi',
      'role': 'member',
      'topics': [],
    });
    expect(User.fromJson(u.toJson()).handle, 'ada');
    expect(User.fromJson(u.toJson()).bio, 'Hi');
  });

  test('gift tiers and providers', () {
    final t = GiftTiers.fromJson({
      'tiers': [
        {
          'id': 'lamp',
          'name': 'Lamp',
          'amount_cents': 499,
          'currency': 'usd',
          'product_id': 'reborn.gift.lamp',
        },
      ],
      'providers': {'stripe': false, 'apple': true, 'google': false},
    });
    expect(t.tiers.single.productId, 'reborn.gift.lamp');
    expect(t.tiers.single.displayPrice, r'$4.99');
    expect(t.enabled('apple'), isTrue);
    expect(t.enabled('google'), isFalse);
  });

  test('share text is the title and the canonical web link', () {
    expect(
      postWebLink('a b', base: 'https://reborn.app/'),
      'https://reborn.app/ideas/a%20b',
    );
    expect(
      postShareText(sampleCard()),
      '${sampleCard().title}\n$webBaseUrl/ideas/meditations-marcus-aurelius--01',
    );
    expect(webBaseUrl, 'https://reborn.app');
  });

  test('compactCount and timeAgo', () {
    expect(compactCount(999), '999');
    expect(compactCount(1200), '1.2k');
    expect(compactCount(12000), '12k');
    expect(compactCount(1000), '1k');
    final now = DateTime(2026, 10, 10, 12);
    expect(
      timeAgo(now.subtract(const Duration(seconds: 5)), now: now),
      'just now',
    );
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2d');
  });
}

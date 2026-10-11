import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/features/circles/circle_screen.dart';
import 'package:reborn/src/features/gifts/gift_store.dart';
import 'package:reborn/src/features/notifications/notifications_controller.dart';
import 'package:reborn/src/features/notifications/push_service.dart';
import 'package:reborn/src/router.dart';

import 'fake_gift_store.dart';
import 'fake_server.dart';
import 'fixtures.dart';

Map<String, dynamic> notificationJson(
  String id, {
  String kind = 'reply',
  String text = 'Bob replied to your comment',
  String? postId = 'p1',
  String? commentId = 'c1',
  String? readAt,
}) => {
  'id': id,
  'kind': kind,
  'text': text,
  'actor': {'id': 'u2', 'handle': 'bob', 'display_name': 'Bob'},
  'post_id': postId,
  'comment_id': commentId,
  'circle_id': null,
  'read_at': readAt,
  'created_at': '2026-10-10T09:00:00Z',
};

Map<String, dynamic> circleJson({
  bool isMember = false,
  String? role,
  int members = 2,
}) => {
  'id': 'k1',
  'name': 'Stoic readers',
  'description': 'Slow reading, one idea a day.',
  'source': {'id': 's1', 'title': 'Meditations'},
  'owner': {'id': 'u2', 'handle': 'bob', 'display_name': 'Bob'},
  'members': members,
  'is_member': isMember,
  'role': role,
  'created_at': '2026-10-01T09:00:00Z',
};

Map<String, dynamic> userMe({bool premium = false}) => {
  'id': 'u1',
  'email': 'a@b.com',
  'handle': 'ada',
  'display_name': 'Ada',
  'bio': '',
  'role': 'member',
  'topics': <String>[],
  'premium': premium,
};

Map<String, dynamic> premiumJson({bool premium = false}) => {
  'plans': [
    {
      'id': 'monthly',
      'name': 'Monthly',
      'amount_cents': 499,
      'currency': 'usd',
      'interval': 'month',
      'product_id': 'reborn.premium.monthly',
    },
    {
      'id': 'yearly',
      'name': 'Yearly',
      'amount_cents': 3999,
      'currency': 'usd',
      'interval': 'year',
      'product_id': 'reborn.premium.yearly',
    },
  ],
  'providers': {'stripe': true, 'apple': true, 'google': true},
  'premium': premium,
  'premium_until': premium ? '2026-11-10T09:00:00Z' : null,
  'subscription': premium
      ? {
          'provider': 'apple',
          'plan': 'monthly',
          'status': 'active',
          'expires_at': '2026-11-10T09:00:00Z',
        }
      : null,
};

void main() {
  testWidgets(
    'inbox: opening it marks the listed items read and clears the badge',
    (tester) async {
      var n1Read = false;
      final server = FakeServer()
        ..on(
          'GET /v1/notifications',
          (_) => {
            'notifications': [
              notificationJson(
                'n1',
                readAt: n1Read ? '2026-10-09T10:00:00Z' : null,
              ),
              notificationJson(
                'n2',
                kind: 'follow',
                text: 'Bob followed you',
                postId: null,
                commentId: null,
                readAt: '2026-10-09T09:00:00Z',
              ),
            ],
            'unread': n1Read ? 0 : 1,
          },
        )
        ..on('POST /v1/notifications/read', (_) {
          n1Read = true;
          return const Reply.empty();
        })
        ..on('GET /v1/posts/p1/comments', (_) => {'comments': <Object>[]})
        ..on('GET /v1/posts/p1', (_) => postJson(cardJson()));
      final container = await pumpApp(tester, server, prefs: signedInPrefs);

      final bell = find.byKey(const ValueKey('notification-bell'));
      expect(bell, findsOneWidget);
      expect(
        find.descendant(of: bell, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
      final unread = find.byKey(const ValueKey('notification-n1'));
      expect(
        find.descendant(
          of: unread,
          matching: find.byKey(const ValueKey('unread-dot')),
        ),
        findsOneWidget,
      );
      // The read one has no dot.
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
      // Opening the inbox marked what it lists read, as on the web: the badge
      // clears, but the new row keeps its dot while the inbox is open.
      expect(server.called('POST /v1/notifications/read').single.body, {
        'ids': ['n1'],
      });
      expect(container.read(unreadCountProvider), 0);
      expect(find.text('Mark all read'), findsNothing);

      await tester.tap(unread);
      await tester.pumpAndSettle();
      // Already marked: no second call.
      expect(server.called('POST /v1/notifications/read'), hasLength(1));
      expect(find.widgetWithText(AppBar, 'Comments'), findsOneWidget);

      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);

      // Leave the inbox and come back: nothing is new any more.
      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.descendant(of: bell, matching: find.text('1')), findsNothing);
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    },
  );

  test('push data opens the right screen', () {
    expect(pushLocation({'kind': 'circle', 'circle_id': 'k1'}), '/circles/k1');
    expect(
      pushLocation({'kind': 'reply', 'post_id': 'p1', 'comment_id': 'c1'}),
      '/posts/p1/comments',
    );
    expect(pushLocation({'kind': 'daily', 'post_id': 'p1'}), '/cards/p1');
    expect(pushLocation({'kind': 'reward'}), '/notifications');
    expect(pushLocation({}), isNull);
  });

  testWidgets('block from a profile, then undo it in settings', (tester) async {
    var blocked = <Map<String, dynamic>>[];
    final server = FakeServer()
      ..on(
        'GET /v1/users/bob',
        (_) => {
          'id': 'u2',
          'handle': 'bob',
          'display_name': 'Bob',
          'followers': 2,
          'is_following': true,
          'is_me': false,
        },
      )
      ..on(
        'GET /v1/users/bob/favorites',
        (_) => {'posts': <Object>[], 'next_cursor': null},
      )
      ..on('GET /v1/me/blocks', (_) => {'blocks': blocked})
      ..on('PUT /v1/blocks/u2', (c) {
        blocked = [
          {
            'id': 'u2',
            'handle': 'bob',
            'display_name': 'Bob',
            'kind': c.body['kind'],
          },
        ];
        return const Reply.empty();
      })
      ..on('DELETE /v1/blocks/u2', (_) {
        blocked = [];
        return const Reply.empty();
      });
    final container = await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/users/bob',
    );

    await tester.tap(find.byKey(const ValueKey('block-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Mute Bob'), findsOneWidget);
    await tester.tap(find.text('Block Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Block Bob?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();
    expect(server.called('PUT /v1/blocks/u2').single.body, {'kind': 'block'});
    expect(find.text('Blocked Bob'), findsOneWidget);

    // The menu now offers to undo it.
    await tester.tap(find.byKey(const ValueKey('block-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Unblock Bob'), findsOneWidget);
    await tester.tapAt(const Offset(10, 600));
    await tester.pumpAndSettle();

    await push(tester, container, '/settings');
    final row = find.byKey(const ValueKey('blocked-u2'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.descendant(of: row, matching: find.text('Undo')));
    await tester.pumpAndSettle();
    expect(server.called('DELETE /v1/blocks/u2'), hasLength(1));
    expect(find.byKey(const ValueKey('blocked-u2')), findsNothing);
  });

  testWidgets('circle: join, see members, post a message with an idea', (
    tester,
  ) async {
    var member = false;
    final server = FakeServer()
      ..on(
        'GET /v1/circles/k1',
        (_) => circleJson(
          isMember: member,
          role: member ? 'member' : null,
          members: member ? 3 : 2,
        ),
      )
      ..on('POST /v1/circles/k1/join', (_) {
        member = true;
        return circleJson(isMember: true, role: 'member', members: 3);
      })
      ..on(
        'GET /v1/circles/k1/members',
        (_) => {
          'members': [
            {
              'id': 'u2',
              'handle': 'bob',
              'display_name': 'Bob',
              'role': 'owner',
              'joined_at': '2026-10-01T09:00:00Z',
            },
            {
              'id': 'u1',
              'handle': 'ada',
              'display_name': 'Ada',
              'role': 'member',
              'joined_at': '2026-10-10T09:00:00Z',
            },
          ],
        },
      )
      ..on('GET /v1/circles/k1/messages', (_) => {'messages': <Object>[]})
      ..on(
        'GET /v1/sources/s1',
        (_) => {
          'source': {...cardJson()['source'] as Map, 'id': 's1'},
          'cards': [cardJson()],
        },
      )
      ..on(
        'POST /v1/circles/k1/messages',
        (c) => Reply({
          'id': 'm1',
          'circle_id': 'k1',
          'body': c.body['body'],
          'post_id': c.body['post_id'],
          'author': {'id': 'u1', 'handle': 'ada', 'display_name': 'Ada'},
          'created_at': '2026-10-10T10:00:00Z',
        }, 201),
      );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/circles/k1',
    );
    expect(find.text('Stoic readers'), findsWidgets);
    expect(find.byKey(const ValueKey('circle-message-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('join-circle')));
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/circles/k1/join'), hasLength(1));
    expect(find.text('3 members'), findsOneWidget);

    // Members, owner first.
    await tester.tap(find.byKey(const ValueKey('circle-members')));
    await tester.pumpAndSettle();
    final owner = find.byKey(const ValueKey('member-u2'));
    expect(owner, findsOneWidget);
    expect(find.descendant(of: owner, matching: find.text('Owner')), findsOne);
    expect(
      tester.getTopLeft(owner).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('member-u1'))).dy),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Attach an idea and send.
    await tester.tap(find.byTooltip('Attach an idea from this book'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(sampleCard().title).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attached-idea')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('circle-message-field')),
      'This one changed my week',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/circles/k1/messages').single.body, {
      'body': 'This one changed my week',
      'post_id': sampleCard().id,
    });
    expect(find.byKey(const ValueKey('message-m1')), findsOneWidget);
    expect(find.text('This one changed my week'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-idea-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('attached-idea')), findsNothing);
  });

  testWidgets('circle: a full circle says so', (tester) async {
    final server = FakeServer()
      ..on('GET /v1/circles/k1', (_) => circleJson(members: 50))
      ..on(
        'POST /v1/circles/k1/join',
        (_) => Reply.error(409, 'circle_full', 'circle is full'),
      );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/circles/k1',
    );
    await tester.tap(find.byKey(const ValueKey('join-circle')));
    await tester.pumpAndSettle();
    expect(find.text(kCircleFull), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('join-circle')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('premium: store purchase is confirmed by the server, then '
      'completed', (tester) async {
    var premium = false;
    final store = FakeGiftStore(GiftPlatform.apple);
    var finishedBeforeServer = true;
    final server = FakeServer()
      ..on('GET /v1/premium', (_) => premiumJson(premium: premium))
      ..on('POST /v1/premium/apple', (_) {
        finishedBeforeServer = store.finishedSubscriptions.isNotEmpty;
        premium = true;
        return premiumJson(premium: true);
      })
      ..on('GET /v1/me', (_) => userMe(premium: premium));
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      giftStore: store,
      location: '/premium',
    );
    expect(find.byKey(const ValueKey('premium-coming-soon')), findsNothing);
    expect(find.text('£1.99 per month'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('plan-monthly')),
        matching: find.text('Subscribe'),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.subscribed, [('reborn.premium.monthly', 'u1')]);
    expect(server.called('POST /v1/premium/apple').single.body, {
      'signed_transaction': 'header.jws-payload.sig',
    });
    expect(finishedBeforeServer, isFalse);
    expect(store.finishedSubscriptions, ['reborn.premium.monthly']);
    expect(find.text("You're Premium"), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('premium: a rejected purchase is not completed', (tester) async {
    final store = FakeGiftStore(GiftPlatform.google);
    final server = FakeServer()
      ..on('GET /v1/premium', (_) => premiumJson())
      ..on(
        'POST /v1/premium/google',
        (_) => Reply.error(409, 'subscription_taken', 'taken'),
      );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      giftStore: store,
      location: '/premium',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('plan-yearly')),
        matching: find.text('Subscribe'),
      ),
    );
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/premium/google').single.body, {
      'product_id': 'reborn.premium.yearly',
      'purchase_token': 'play-token',
    });
    expect(store.finishedSubscriptions, isEmpty);
    expect(
      find.text('This subscription belongs to another Reborn account.'),
      findsOneWidget,
    );
  });

  testWidgets('premium is "coming soon" without a store', (tester) async {
    final server = FakeServer()..on('GET /v1/premium', (_) => premiumJson());
    await pumpApp(tester, server, prefs: signedInPrefs, location: '/premium');
    expect(find.byKey(const ValueKey('premium-coming-soon')), findsOneWidget);
  });

  testWidgets('referral code and timezone are sent at sign-up', (tester) async {
    final server = FakeServer()
      ..on(
        'POST /v1/auth/register',
        (_) => Reply({'token': 'tok', 'user': userMe()}, 201),
      );
    final container = await pumpApp(
      tester,
      server,
      location: '/join?ref=ada7',
      timezone: 'Europe/London',
    );
    // The invite link prefills the code.
    expect(find.text('ada7'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Bea',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'bea@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'longpassword',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/auth/register').single.body, {
      'email': 'bea@example.com',
      'password': 'longpassword',
      'display_name': 'Bea',
      'timezone': 'Europe/London',
      'referral_code': 'ADA7',
    });
    expect(container.read(sessionProvider).signedIn, isTrue);
  });

  testWidgets('sign-up without a code sends none', (tester) async {
    final server = FakeServer()
      ..on(
        'POST /v1/auth/register',
        (_) => Reply({'token': 'tok', 'user': userMe()}, 201),
      );
    await pumpApp(tester, server, location: '/register');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Bea',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'bea@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'longpassword',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    final body = server.called('POST /v1/auth/register').single.body as Map;
    expect(body.containsKey('referral_code'), isFalse);
    expect(body.containsKey('timezone'), isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/features/auth/forgot_password_screen.dart';

import 'fake_server.dart';
import 'fixtures.dart';

Map<String, dynamic> userJson({String handle = 'ada', String bio = ''}) => {
  'id': 'u1',
  'email': 'a@b.com',
  'handle': handle,
  'display_name': 'Ada',
  'bio': bio,
  'role': 'member',
  'topics': <String>[],
};

void main() {
  testWidgets('forgot password from sign in', (tester) async {
    final server = FakeServer()
      ..on('POST /v1/auth/forgot', (_) => const Reply.empty(202));
    await pumpApp(tester, server, location: '/signin');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'a@b.com',
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
    // The email typed on sign in is carried over.
    expect(find.text('a@b.com'), findsOneWidget);
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(server.called('POST /v1/auth/forgot').single.body, {
      'email': 'a@b.com',
    });
    expect(find.text(kForgotPasswordSent), findsOneWidget);
    expect(kForgotPasswordSent, "If an account exists, we've emailed a link.");
  });

  testWidgets('settings: handle taken, then saved', (tester) async {
    var taken = true;
    final server = FakeServer()
      ..on('PATCH /v1/me', (c) {
        if (taken) {
          return Reply.error(409, 'handle_taken', 'that handle is taken');
        }
        return userJson(
          handle: c.body['handle'] as String? ?? 'ada',
          bio: c.body['bio'] as String? ?? '',
        );
      });
    final container = await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/settings',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-handle')),
      'bob',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-bio')),
      'Reader',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('That handle is taken. Try another.'), findsOneWidget);
    expect(server.calls.last.body, {'handle': 'bob', 'bio': 'Reader'});

    // Invalid handles are caught before sending.
    await tester.enterText(find.byKey(const ValueKey('settings-handle')), 'a!');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use 3-30 lowercase letters, digits or _'),
      findsOneWidget,
    );
    expect(server.called('PATCH /v1/me'), hasLength(1));

    taken = false;
    await tester.enterText(
      find.byKey(const ValueKey('settings-handle')),
      'ada_l',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    final user = container.read(sessionProvider).user!;
    expect(user.handle, 'ada_l');
    expect(user.bio, 'Reader');
  });

  testWidgets('delete account asks first, then signs out', (tester) async {
    final server = FakeServer()
      ..on('DELETE /v1/me', (_) => const Reply.empty());
    final container = await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/settings',
    );
    await tester.tap(find.byKey(const ValueKey('delete-account')));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.log, isNot(contains('DELETE /v1/me')));

    await tester.tap(find.byKey(const ValueKey('delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(server.log, contains('DELETE /v1/me'));
    expect(container.read(sessionProvider).signedIn, isFalse);
    expect(
      container.read(sharedPreferencesProvider).getString('auth.token'),
      isNull,
    );
    expect(find.text('Your account has been deleted.'), findsOneWidget);
    expect(currentPath(container), '/home');
  });

  testWidgets('profile by handle: counts, follow, favourites', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/users/bob',
        (_) => {
          'id': 'u2',
          'handle': 'bob',
          'display_name': 'Bob',
          'bio': 'Reads Stoics',
          'followers': 2,
          'following': 5,
          'favorites': 1,
          'is_following': false,
          'is_me': false,
        },
      )
      ..on(
        'GET /v1/users/bob/favorites',
        (_) => {
          'posts': [postJson(cardJson())],
          'next_cursor': null,
        },
      )
      ..on(
        'PUT /v1/follows/user/u2',
        (_) => {'followers': 3, 'is_following': true},
      );
    await pumpApp(tester, server, prefs: signedInPrefs, location: '/users/bob');
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('@bob'), findsWidgets);
    expect(find.text('Reads Stoics'), findsOneWidget);
    expect(find.text('2 followers'), findsOneWidget);
    // Cards come first; favourites are a tab away.
    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text(sampleCard().title), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-button')));
    await tester.pumpAndSettle();
    expect(find.text('3 followers'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('signed out follow goes to sign in', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/users/bob',
        (_) => {
          'id': 'u2',
          'handle': 'bob',
          'display_name': 'Bob',
          'followers': 2,
          'is_following': false,
          'is_me': false,
        },
      )
      ..on(
        'GET /v1/users/bob/favorites',
        (_) => {'posts': <Object>[], 'next_cursor': null},
      );
    await pumpApp(tester, server, location: '/users/bob');
    await tester.tap(find.byKey(const ValueKey('follow-button')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(server.log.where((r) => r.startsWith('PUT')), isEmpty);
  });

  testWidgets('source screen has a follow button and author links', (
    tester,
  ) async {
    final id = sampleCard().source.id;
    final server = FakeServer()
      ..on(
        'GET /v1/sources/$id',
        (_) => {
          'source': cardJson()['source'],
          'cards': [cardJson()],
          'follow': {'followers': 7, 'is_following': true},
        },
      )
      ..on(
        'DELETE /v1/follows/source/$id',
        (_) => {'followers': 6, 'is_following': false},
      );
    await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/sources/$id',
    );
    expect(find.text('7 followers'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-button')));
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('6 followers'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-author-Marcus Aurelius')),
      findsOneWidget,
    );
  });

  testWidgets('following list and favourites from the profile', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/me/following',
        (_) => {
          'following': [
            {'kind': 'user', 'target': 'u2', 'label': 'Bob', 'handle': 'bob'},
            {
              'kind': 'source',
              'target': 'meditations-marcus-aurelius',
              'label': 'Meditations',
            },
            {
              'kind': 'author',
              'target': 'Marcus Aurelius',
              'label': 'Marcus Aurelius',
            },
          ],
        },
      )
      ..on(
        'GET /v1/me/favorites',
        (_) => {
          'posts': [postJson(healthCard().toJson())],
          'next_cursor': null,
        },
      )
      ..on('GET /v1/me', (_) => userJson());
    await pumpApp(tester, server, prefs: signedInPrefs, location: '/profile');
    expect(find.text('@ada · a@b.com'), findsOneWidget);

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Meditations'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text(healthCard().title), findsOneWidget);
    expect(server.log, contains('GET /v1/me/favorites'));
  });
}

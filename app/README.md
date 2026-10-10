# Reborn app (Flutter: Android and iOS)

The Reborn client: one-minute idea cards from books, with a daily idea, search,
stashes, spaced review and quizzes, an "Ask" agent, and community contributions.
It talks to the backend described in [`../docs/API.md`](../docs/API.md).

The web app is built separately in Next.js. This project keeps its `web/`
platform folder only so `flutter build web` can be used as a compile check on
machines without an Android SDK. Running in Chrome works for quick UI checks
during development.

## Run

The API base URL comes from `--dart-define=API_BASE_URL=...` and defaults to
`http://localhost:8080`.

```sh
cd app
flutter pub get

# Chrome (quick UI checks only; the real web app is Next.js)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080

# Android emulator: the host machine's localhost is 10.0.2.2
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8080

# iOS simulator shares the host network
flutter run -d ios --dart-define=API_BASE_URL=http://localhost:8080
```

For local development, `android/app/src/main/AndroidManifest.xml` declares the
`INTERNET` permission and `android:usesCleartextTraffic="true"` so the app can
reach a plain `http://` backend. Use HTTPS and drop cleartext before a release
build.

## Check

```sh
flutter analyze
flutter test
flutter build web     # compile check when no Android SDK is available
flutter build apk --dart-define=API_BASE_URL=https://api.example.com
```

## Layout

```
lib/
  main.dart                    loads SharedPreferences, starts ProviderScope
  src/
    app.dart                   MaterialApp.router, global "Offline" banner
    router.dart                go_router routes (5-tab StatefulShellRoute + pages)
    theme.dart                 Material 3 light/dark themes, reading width (680px)
    api/
      api_client.dart          package:http client for every endpoint, ApiException
      models.dart              hand-written models with fromJson/toJson
    data/
      offline_cache.dart       JSON cache in shared_preferences
      repository.dart          network-first reads with offline fallback
      providers.dart           Riverpod providers, session (token) and topic prefs
      speaker.dart             flutter_tts wrapper for the Listen button
    widgets/common.dart        shared widgets (sign-in prompt, errors, card tile, menu)
    features/
      onboarding/  home/  daily/  card/  source/  search/  stashes/
      review/  ask/  contribute/  moderation/  auth/  profile/  shell/
test/                          model, client, cache, Ask and widget tests
```

## Behaviour notes

- **Signed out**, the feed, daily idea, search, sources and cards all work.
  Stashes, Review, Ask and Contribute show a sign-in prompt. The token is stored
  in shared_preferences, and a 401 signs the user out.
- **Topics** chosen during onboarding are saved locally. When the user is signed
  in they are also saved with `PATCH /v1/me`. Local topics are pushed to a new
  account on sign-in if the account has none.
- **Feed**: vertically paged cards, loaded with `next_cursor`. Overscrolling a
  long card turns the page. Views are recorded with `POST /v1/cards/{id}/view`
  when signed in.
- **Card**: the `credit` line is always shown and opens the source page. The
  `disclaimer` is always shown when present. A `health` card with no text gets
  the default notice. Listen reads the title, body and "Apply it". Share copies
  a plain-text version that keeps the credit.
- **Offline**: feed pages, the daily idea, topics, sources, stashes (with all
  their cards, prefetched whenever the stash list loads) and every opened card
  are cached as JSON. When a request fails because the network is unreachable,
  the app serves the cache and shows a small "Offline" banner.
- **Review**: due cards are shown one at a time. If a card has a quiz, the
  question comes first, then the card, then Again/Hard/Good/Easy. **Quiz mode**
  records `good` for a right answer and `again` for a wrong one.
- **Ask**: sends the full history and turns `[card-id]` citations into chips
  that open the card. `503 agent_unavailable` and `429` show friendly messages,
  and the question is put back in the input box.
- **Moderation** is in the profile menu for users with `role == "moderator"`.

# Reborn app (Flutter: Android and iOS)

The Reborn client: one-minute idea cards from books, with a timeline, a daily
idea, search, stashes, spaced review and quizzes, an "Ask" agent, community
contributions, a social layer (reactions, favourites, comments, shares,
gifts and follows), notifications and push, streaks, blocking, Discover, public
stashes, book circles, Premium, referrals and a moderator dashboard.
It talks to the backend described in [`../docs/API.md`](../docs/API.md).

The web app is built separately in Next.js. This project keeps its `web/`
platform folder only so `flutter build web` can be used as a compile check on
machines without an Android SDK. Running in Chrome works for quick UI checks
during development.

## Run

The API base URL comes from `--dart-define=API_BASE_URL=...` and defaults to
`http://localhost:8080`. The website's base URL (used for shared links) comes
from `--dart-define=WEB_BASE_URL=...` and defaults to `https://reborn.app`.

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

Push notifications use Firebase Cloud Messaging and are optional. Without
`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
(plus the Push Notifications capability and an APNs key in Firebase on iOS)
the app runs normally and skips push quietly. Add those files from the
Firebase console to turn push on.

For local development, `android/app/src/main/AndroidManifest.xml` declares the
`INTERNET` permission and `android:usesCleartextTraffic="true"` so the app can
reach a plain `http://` backend. Use HTTPS and drop cleartext before a release
build.

## Check

```sh
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn   # compile check without an Android SDK
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
      device_timezone.dart     the device's IANA timezone (flutter_timezone)
    widgets/common.dart        shared widgets (sign-in prompt, errors, card tile, menu)
    features/
      onboarding/  home/ (swipe feed)  daily/  card/  source/  search/
      stashes/  review/  ask/  contribute/  moderation/  auth/  profile/
      shell/
      timeline/    home tab: timeline, seen tracking, "caught up" line
      post/        PostView (reactions, favourite, comments, share, gift),
                   optimistic post store, native share
      comments/    comments screen with one level of replies
      social/      profiles by handle, authors, following, favourites
      settings/    handle, bio, daily goal, timezone, push toggles, blocked
                   list, delete account
      gifts/       gift sheet, in-app purchase store and server hand-off
      notifications/  bell, inbox, optional Firebase push service
      streak/      streak card (current streak, today vs goal, last 7 days)
      blocks/      block/mute menu and the blocked list
      discover/    Discover tab: trending by topic, new, books, authors, circles
      circles/     circle list, create form, circle screen with messages
      premium/     Premium screen, badge, subscription purchase service
      referrals/   invite screen
      admin/       moderator dashboard with a CustomPaint chart
test/                          model, client, cache, Ask and widget tests
```

## Behaviour notes

- **Signed out**, the feed, daily idea, search, sources and cards all work.
  Stashes, Review, Ask and Contribute show a sign-in prompt. The token is stored
  in shared_preferences, and a 401 signs the user out.
- **Topics** chosen during onboarding are saved locally. When the user is signed
  in they are also saved with `PATCH /v1/me`. Local topics are pushed to a new
  account on sign-in if the account has none.
- **Timeline** (Home tab): `GET /v1/timeline` with infinite scroll and pull to
  refresh, plus topic chips. Each post shows why it is there ("From
  Meditations", "Because you follow Marcus Aurelius", "Bob favourited this", or
  the topic). Signed in, a post counts as seen once at least half of it (or
  the whole viewport, for posts taller than the screen) has been visible for a
  second; ids are batched to `POST /v1/seen`. "You're all caught up" marks where
  unseen posts end. Signed out, a sign-up card sits at the top.
- **Swipe feed** (`/feed`, from the timeline's app bar): vertically paged cards
  from `GET /v1/feed`. Views are recorded with `POST /v1/cards/{id}/view`.
- **Posts**: every card is a post. The card screen and the timeline share
  `PostView`: five reactions with counts (one per person, tap again to clear),
  favourite, comments, share and gift, all updated optimistically and rolled
  back on failure. Signed out, reacting, favouriting, gifting, commenting and
  following go to sign in; reading comments and sharing work signed out.
- **Share** opens the platform share sheet (share_plus) with the title and the
  canonical link `WEB_BASE_URL/ideas/{id}`, and counts it with channel
  `native` (`copy_link` if the sheet is unavailable and the link is copied).
- **Gifts** support Reborn. The sheet lists `GET /v1/gifts/tiers`; purchases are
  consumable in-app products (`reborn.gift.spark|lamp|sun`) through the
  official `in_app_purchase` plugin. iOS uses StoreKit 2 (the plugin default)
  and sends the transaction JWS (`verificationData.serverVerificationData`) to
  `POST /v1/posts/{id}/gifts/apple`; Android sends the product id and purchase
  token to `.../gifts/google`. The purchase is finished/consumed only after the
  server accepts it; otherwise it stays with the store and is retried for the
  same post when the store re-delivers it (listened for from app start). When
  the platform's provider is off, the store is unavailable, or on web, the
  tiers show with "Gifts are coming soon". The products must exist in App
  Store Connect / the Play Console and the app needs the In-App Purchase
  capability before release.
- **Follow** books (source screen), authors (tap an author name) and people
  (profile by handle). The profile menu has Favourites, Following and Settings
  (handle, bio, and in-app account deletion with `DELETE /v1/me`).
- **Forgot password?** on sign in calls `POST /v1/auth/forgot`; the emailed
  link opens the website's reset page.
- **Card**: the `credit` line is always shown and opens the source page. The
  `disclaimer` is always shown when present. A `health` card with no text gets
  the default notice. Listen reads the title, body and "Apply it".
- **Offline**: timeline and feed pages, posts, the daily idea, topics, sources, stashes (with all
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
- **Notifications**: the bell on the timeline and Discover shows the unread
  count from `GET /v1/notifications` (refreshed on pull, on app resume and when
  a push arrives). Opening an item marks it read (`POST /v1/notifications/read`
  with its id; "Mark all read" sends no body) and opens its circle, comments,
  post or the actor's profile.
- **Push** (iOS and Android only): when Firebase is configured, the app asks for
  permission after sign-in, registers the FCM token with `POST /v1/devices`
  (`platform` `ios` or `android`) and deletes it with `DELETE /v1/devices/{token}`
  on sign-out. Tapping a push opens the screen for its `post_id`, `comment_id`,
  `circle_id` and `kind`. Without Firebase config nothing is asked or sent.
- **Streak**: a card on the timeline and profile shows the current streak,
  today's ideas against the daily goal, and the last seven days
  (`GET /v1/me/streak`). Settings has the daily goal, the timezone (the
  device's IANA zone is sent at sign-up and can be applied later) and a switch
  per push kind (`notify` on `PATCH /v1/me`).
- **Block and mute** from a profile's menu or a comment's menu. Blocking asks
  first. Settings lists blocked and muted people with Undo.
- **Discover** (the fourth tab, which replaces Search; search is in its search
  bar): trending posts with topic chips (`GET /v1/trending`), plus new posts,
  popular books, popular authors and circles from `GET /v1/discover`.
- **Public stashes**: a switch on each stash makes it public. Profiles have a
  Stashes tab that opens the public stash screen (`/s/{id}`).
- **Book circles**: a list of your circles and all circles (profile menu), a
  circles section with a create form on each book's screen, and a circle
  screen with the member list (`GET /v1/circles/{id}/members`, owner first),
  join and leave. Messages refresh every 10 seconds while the screen is open; a
  message can attach an idea from the book, which opens the post. You can
  delete your own messages; circle owners and moderators can delete any.
  `409 circle_full` says the circle is full.
- **Premium**: plans, status and benefits from `GET /v1/premium`. On iOS and
  Android the plans are auto-renewing subscriptions `reborn.premium.monthly`
  and `reborn.premium.yearly` bought with `in_app_purchase`, with the user id as
  `applicationUserName` (Apple's `appAccountToken`, Play's obfuscated account
  id). iOS sends the StoreKit 2 JWS to `POST /v1/premium/apple`; Android sends
  the product id and purchase token to `POST /v1/premium/google`. The purchase
  is completed (finished/acknowledged) only after the server confirms it.
  Restore purchases re-sends owned subscriptions; Manage subscription opens the
  store's subscription page. Without a store, or when the provider is off, the
  plans show "coming soon". Your own profile shows a Premium badge. The
  subscription products must exist in App Store Connect and the Play Console.
- **Referrals**: the invite screen shows your code, shares
  `WEB_BASE_URL/join?ref=CODE` and counts invited and rewarded friends. Sign-up
  has an optional referral code field, prefilled by `/join?ref=CODE` links.
- **Dashboard** (moderators, in the profile menu): stat tiles, a 30-day chart
  of active users and sign-ups drawn with CustomPaint, retention, engagement,
  revenue, moderation queues and top posts from `GET /v1/admin/stats`.

New dependencies for these features: `firebase_core`, `firebase_messaging`
and `flutter_timezone`.

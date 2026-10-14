# Test signing key

`reborn-test.jks` signs the sideloaded test APKs (the `apk-latest` GitHub release and
local `flutter build apk --release`). Every build signed with the same key can be
installed over the previous one; with GitHub's throwaway debug key each build had a
different signature, so phones refused the update and kept the old app.

It is deliberately not secret (store and key password: `reborn-test`). Never use it for
the Play Store: create a private upload key for that and keep it out of the repo.

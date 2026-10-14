#!/bin/sh
# Migrates, imports the card library in the background (seeding is idempotent and
# never deletes cards), and serves. Set SEED_ON_START=0 to skip the import.
set -e
if [ -n "$PORT" ]; then export ADDR=":$PORT"; fi
reborn migrate
if [ "${SEED_ON_START:-1}" = "1" ]; then
  (reborn seed "$CONTENT_DIR" || echo "seed failed; serving the existing library") &
fi
exec reborn serve

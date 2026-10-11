-- Social layer: handles, password resets, the timeline's publish time,
-- follows, favourites, reactions, comments, shares and gifts.

ALTER TABLE users ADD COLUMN handle text;
ALTER TABLE users ADD COLUMN bio text NOT NULL DEFAULT '';
UPDATE users SET handle = 'user' || substr(replace(id::text, '-', ''), 1, 10) WHERE handle IS NULL;
ALTER TABLE users ALTER COLUMN handle SET NOT NULL;
CREATE UNIQUE INDEX users_handle_idx ON users (lower(handle));

-- A card becomes a post the first time it is imported; re-seeding keeps the time.
ALTER TABLE cards ADD COLUMN published_at timestamptz NOT NULL DEFAULT now();
UPDATE cards SET published_at = created_at;
CREATE INDEX cards_published_idx ON cards (published_at DESC) WHERE status = 'published';
CREATE INDEX cards_contributor_idx ON cards (contributed_by) WHERE contributed_by IS NOT NULL;
CREATE INDEX sources_authors_idx ON sources USING gin (authors);

CREATE TABLE password_resets (
    token_hash text PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX password_resets_user_idx ON password_resets (user_id);

-- target is a user id, a source id or an author name, depending on kind.
CREATE TABLE follows (
    follower_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('user', 'source', 'author')),
    target      text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, kind, target)
);
CREATE INDEX follows_target_idx ON follows (kind, target);

CREATE TABLE favorites (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id    text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, card_id)
);
CREATE INDEX favorites_card_idx ON favorites (card_id);

CREATE TABLE reactions (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id    text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('like', 'love', 'insightful', 'inspiring', 'helpful')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, card_id)
);
CREATE INDEX reactions_card_idx ON reactions (card_id);

CREATE TABLE comments (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id    text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id  uuid REFERENCES comments(id) ON DELETE CASCADE,
    body       text NOT NULL,
    status     text NOT NULL DEFAULT 'visible' CHECK (status IN ('visible', 'hidden')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_card_idx ON comments (card_id, created_at);

CREATE TABLE comment_reports (
    comment_id uuid NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason     text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id)
);

CREATE TABLE shares (
    id         bigserial PRIMARY KEY,
    card_id    text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
    channel    text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX shares_card_idx ON shares (card_id);

-- A gift row is created when checkout starts and marked paid when the store confirms it.
CREATE TABLE gifts (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid REFERENCES users(id) ON DELETE SET NULL,
    card_id      text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    tier         text NOT NULL,
    amount_cents int  NOT NULL,
    currency     text NOT NULL,
    provider     text NOT NULL CHECK (provider IN ('stripe', 'apple', 'google')),
    provider_ref text,
    status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'refunded')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    paid_at      timestamptz,
    UNIQUE (provider, provider_ref)
);
CREATE INDEX gifts_card_idx ON gifts (card_id) WHERE status = 'paid';

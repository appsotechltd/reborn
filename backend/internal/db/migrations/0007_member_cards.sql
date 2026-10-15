-- Member cards: idea cards people write themselves. They live in the cards
-- table (so reactions, comments, favourites, collections and gifts all work on
-- them), under one shared "members" source, with the writer in author_id.
-- Members file their cards under categories of their own, and premium members
-- can make an image, an audio reading or an illustrated video for each card
-- with AI units. Library-only lists (books, authors, search, sitemap) skip
-- member cards; the timeline and profiles show the public ones.

INSERT INTO sources (id, title, authors, kind, url, licence, licence_url, attribution, retrieved_at)
VALUES ('reborn-members', 'Written by Reborn members', '{}', 'member', '', 'Member card', '', 'a Reborn member', current_date)
ON CONFLICT (id) DO NOTHING;

-- A member's own categories for their cards.
CREATE TABLE member_categories (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX member_categories_name_idx ON member_categories (user_id, lower(name));

ALTER TABLE cards ADD COLUMN author_id uuid REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE cards ADD COLUMN category_id uuid REFERENCES member_categories(id) ON DELETE SET NULL;
-- AI-made media for member cards: {"image": {...}, "audio": {...}, "video": {...}}.
ALTER TABLE cards ADD COLUMN media jsonb NOT NULL DEFAULT '{}';
-- Who may see a member's published card: everyone, their followers, or their
-- paying subscribers. Subscribers see followers-only cards too.
ALTER TABLE cards ADD COLUMN audience text NOT NULL DEFAULT 'everyone' CHECK (audience IN ('everyone', 'followers', 'subscribers'));
CREATE INDEX cards_author_idx ON cards (author_id, created_at DESC) WHERE author_id IS NOT NULL;

-- 'private' cards are seen only by their writer; 'hidden' ones were taken down
-- (by a moderator, by reports, or by the library seed); 'deleted' ones were
-- deleted by their writer but are kept, emptied, because gifts point at them.
ALTER TABLE cards DROP CONSTRAINT cards_status_check;
ALTER TABLE cards ADD CONSTRAINT cards_status_check CHECK (status IN ('published', 'hidden', 'private', 'deleted'));

CREATE TABLE card_reports (
    card_id    text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason     text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (card_id, user_id)
);

-- Gifts on a member's card are shared with the writer. author_cents is their
-- share, worked out when the gift is made: the price less the payment fee,
-- less Reborn's commission.
ALTER TABLE gifts ADD COLUMN author_id uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE gifts ADD COLUMN fee_cents int NOT NULL DEFAULT 0;
ALTER TABLE gifts ADD COLUMN author_cents int NOT NULL DEFAULT 0;
CREATE INDEX gifts_author_idx ON gifts (author_id, paid_at DESC) WHERE author_id IS NOT NULL AND status = 'paid';

ALTER TABLE notifications DROP CONSTRAINT notifications_kind_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_kind_check
    CHECK (kind IN ('daily', 'reply', 'follow', 'circle', 'reward', 'gift', 'subscriber'));

ALTER TABLE ai_usage DROP CONSTRAINT ai_usage_kind_check;
ALTER TABLE ai_usage ADD CONSTRAINT ai_usage_kind_check
    CHECK (kind IN ('text', 'chart', 'voice', 'sketch', 'illustration', 'picture', 'audio', 'video'));

-- Paid subscriptions to writers. A writer turns subscriptions on and picks a
-- monthly price; subscribers can read the writer's subscribers-only cards
-- until expires_at. On the web it is a Stripe subscription that renews; in
-- the apps each purchase is a 30-day pass that extends expires_at.
CREATE TABLE writer_plans (
    user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    tier       text NOT NULL,
    enabled    boolean NOT NULL DEFAULT true,
    pitch      text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE writer_subscriptions (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subscriber_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    writer_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tier          text NOT NULL,
    provider      text NOT NULL CHECK (provider IN ('stripe', 'apple', 'google')),
    stripe_ref    text UNIQUE,                     -- the Stripe subscription id
    renews        boolean NOT NULL DEFAULT false,  -- a Stripe subscription that will renew
    expires_at    timestamptz NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subscriber_id, writer_id)
);
CREATE INDEX writer_subscriptions_writer_idx ON writer_subscriptions (writer_id, expires_at);

-- Each payment for a subscription, with the writer's share.
CREATE TABLE writer_payments (
    id            bigserial PRIMARY KEY,
    writer_id     uuid REFERENCES users(id) ON DELETE SET NULL,
    subscriber_id uuid REFERENCES users(id) ON DELETE SET NULL,
    tier          text NOT NULL,
    amount_cents  int NOT NULL,
    currency      text NOT NULL,
    fee_cents     int NOT NULL,
    author_cents  int NOT NULL,
    provider      text NOT NULL,
    provider_ref  text NOT NULL,
    paid_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_ref)
);
CREATE INDEX writer_payments_writer_idx ON writer_payments (writer_id, paid_at DESC);

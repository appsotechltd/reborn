-- Engagement and growth: notifications, streaks, blocking, public stashes,
-- book circles, premium, referrals.

ALTER TABLE users ADD COLUMN timezone text NOT NULL DEFAULT 'UTC';
ALTER TABLE users ADD COLUMN daily_goal int NOT NULL DEFAULT 3 CHECK (daily_goal BETWEEN 1 AND 50);
ALTER TABLE users ADD COLUMN notify jsonb NOT NULL DEFAULT '{"daily": true, "replies": true, "follows": true, "circles": true}';
ALTER TABLE users ADD COLUMN last_daily_push date;
ALTER TABLE users ADD COLUMN referral_code text;
ALTER TABLE users ADD COLUMN referred_by uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE users ADD COLUMN referral_rewarded_at timestamptz;
UPDATE users SET referral_code = upper(substr(md5(id::text || random()::text), 1, 8)) WHERE referral_code IS NULL;
ALTER TABLE users ALTER COLUMN referral_code SET NOT NULL;
CREATE UNIQUE INDEX users_referral_code_idx ON users (referral_code);
CREATE INDEX users_referred_by_idx ON users (referred_by) WHERE referred_by IS NOT NULL;
CREATE INDEX users_created_idx ON users (created_at);

-- Push notification targets (FCM registration tokens).
CREATE TABLE devices (
    token      text PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform   text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_user_idx ON devices (user_id);

-- The in-app notification inbox; push is sent alongside.
CREATE TABLE notifications (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('daily', 'reply', 'follow', 'circle', 'reward')),
    actor_id   uuid REFERENCES users(id) ON DELETE CASCADE,
    card_id    text REFERENCES cards(id) ON DELETE CASCADE,
    comment_id uuid REFERENCES comments(id) ON DELETE CASCADE,
    circle_id  uuid,
    text       text NOT NULL,
    read_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

-- One row per user per local day with how many ideas they read.
CREATE TABLE activity_days (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day     date NOT NULL,
    ideas   int  NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, day)
);
CREATE INDEX activity_days_day_idx ON activity_days (day);

-- kind 'block' hides both ways and removes follows; 'mute' only hides them from you.
CREATE TABLE blocks (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('block', 'mute')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, blocked_id),
    CHECK (user_id <> blocked_id)
);
CREATE INDEX blocks_blocked_idx ON blocks (blocked_id);

ALTER TABLE stashes ADD COLUMN is_public boolean NOT NULL DEFAULT false;
CREATE INDEX stashes_public_idx ON stashes (user_id) WHERE is_public;

CREATE TABLE circles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    description text NOT NULL DEFAULT '',
    source_id   text NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    owner_id    uuid REFERENCES users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX circles_source_idx ON circles (source_id);

CREATE TABLE circle_members (
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id)
);
CREATE INDEX circle_members_user_idx ON circle_members (user_id);

CREATE TABLE circle_messages (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id  uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id    text REFERENCES cards(id) ON DELETE SET NULL,
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX circle_messages_circle_idx ON circle_messages (circle_id, created_at);

-- Paid subscriptions, one row per store subscription.
CREATE TABLE subscriptions (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider     text NOT NULL CHECK (provider IN ('stripe', 'apple', 'google')),
    provider_ref text NOT NULL,
    plan         text NOT NULL,
    status       text NOT NULL,
    expires_at   timestamptz NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_ref)
);
CREATE INDEX subscriptions_user_idx ON subscriptions (user_id, expires_at DESC);

-- Free premium time, from referrals.
CREATE TABLE premium_grants (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason     text NOT NULL,
    starts_at  timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX premium_grants_user_idx ON premium_grants (user_id, expires_at DESC);

ALTER TABLE users ADD COLUMN stripe_customer_id text;

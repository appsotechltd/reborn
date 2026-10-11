-- Reborn AI: a premium chat assistant (text, voice, pictures, charts) that
-- spends AI units. Premium includes a monthly allowance; top-up packs add
-- units that never expire and are spent once the allowance runs out.

CREATE TABLE ai_wallets (
    user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    period_start   timestamptz NOT NULL,           -- first day (UTC) of the month the allowance counts
    allowance_used int NOT NULL DEFAULT 0 CHECK (allowance_used >= 0),
    topup_units    int NOT NULL DEFAULT 0 CHECK (topup_units >= 0),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ai_conversations (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_conversations_user_idx ON ai_conversations (user_id, updated_at DESC);

CREATE TABLE ai_messages (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    role            text NOT NULL CHECK (role IN ('user', 'assistant')),
    content         text NOT NULL,
    voice           boolean NOT NULL DEFAULT false, -- the user spoke it, or asked for it spoken
    citations       text[] NOT NULL DEFAULT '{}',   -- card ids the reply cited
    attachments     jsonb NOT NULL DEFAULT '[]',    -- pictures and charts
    units           int NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_messages_conversation_idx ON ai_messages (conversation_id, created_at);

-- One row per charge, so members can see where their units went.
CREATE TABLE ai_usage (
    id             bigserial PRIMARY KEY,
    user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind           text NOT NULL CHECK (kind IN ('text', 'chart', 'voice', 'sketch', 'illustration', 'picture')),
    units          int NOT NULL CHECK (units > 0),
    from_allowance int NOT NULL,
    from_topup     int NOT NULL,
    message_id     uuid REFERENCES ai_messages(id) ON DELETE SET NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_usage_user_idx ON ai_usage (user_id, created_at DESC);

CREATE TABLE ai_topups (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid REFERENCES users(id) ON DELETE SET NULL,
    pack         text NOT NULL,
    units        int NOT NULL CHECK (units > 0),
    amount_cents int NOT NULL,
    currency     text NOT NULL,
    provider     text NOT NULL CHECK (provider IN ('stripe', 'apple', 'google')),
    provider_ref text,
    status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'refunded')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    paid_at      timestamptz,
    UNIQUE (provider, provider_ref)
);

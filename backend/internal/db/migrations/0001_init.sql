CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE topics (
    slug       text PRIMARY KEY,
    name       text NOT NULL,
    sort_order int  NOT NULL
);

CREATE TABLE sources (
    id           text PRIMARY KEY,
    title        text NOT NULL,
    authors      text[] NOT NULL,
    kind         text NOT NULL,
    url          text NOT NULL,
    licence      text NOT NULL,
    licence_url  text NOT NULL,
    attribution  text NOT NULL,
    publisher    text,
    year         int,
    language     text NOT NULL DEFAULT 'en',
    translator   text,
    retrieved_at date NOT NULL,
    notes        text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    display_name  text NOT NULL,
    role          text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'moderator')),
    topics        text[] NOT NULL DEFAULT '{}',
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cards (
    id              text PRIMARY KEY,
    source_id       text NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    topic           text NOT NULL REFERENCES topics(slug),
    tags            text[] NOT NULL DEFAULT '{}',
    title           text NOT NULL,
    body            text NOT NULL,
    quote           text,
    apply_it        text NOT NULL,
    locator         text,
    health          boolean NOT NULL DEFAULT false,
    language        text NOT NULL DEFAULT 'en',
    quiz            jsonb,
    status          text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'hidden')),
    contributed_by  uuid REFERENCES users(id) ON DELETE SET NULL,
    content_hash    text NOT NULL,
    embedding       vector(1024),
    embedding_model text,
    search          tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', title), 'A') ||
        setweight(to_tsvector('english', body), 'B') ||
        setweight(to_tsvector('english', apply_it), 'C') ||
        setweight(to_tsvector('english', coalesce(quote, '')), 'C')
    ) STORED,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cards_source_idx ON cards (source_id);
CREATE INDEX cards_topic_idx ON cards (topic) WHERE status = 'published';
CREATE INDEX cards_search_idx ON cards USING gin (search);
CREATE INDEX cards_tags_idx ON cards USING gin (tags);
CREATE INDEX cards_embedding_idx ON cards USING hnsw (embedding vector_cosine_ops);

CREATE TABLE card_views (
    user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id   text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    viewed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, card_id)
);

CREATE TABLE stashes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        text NOT NULL,
    description text NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

CREATE TABLE stash_cards (
    stash_id uuid NOT NULL REFERENCES stashes(id) ON DELETE CASCADE,
    card_id  text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    added_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (stash_id, card_id)
);

CREATE TABLE reviews (
    user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id          text NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    ease             real NOT NULL DEFAULT 2.5,
    interval_days    int  NOT NULL DEFAULT 0,
    reps             int  NOT NULL DEFAULT 0,
    lapses           int  NOT NULL DEFAULT 0,
    due_at           timestamptz NOT NULL DEFAULT now(),
    last_reviewed_at timestamptz,
    PRIMARY KEY (user_id, card_id)
);
CREATE INDEX reviews_due_idx ON reviews (user_id, due_at);

CREATE TABLE contributions (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    source         jsonb NOT NULL,
    topic          text NOT NULL REFERENCES topics(slug),
    title          text NOT NULL,
    body           text NOT NULL,
    apply_it       text NOT NULL,
    tags           text[] NOT NULL DEFAULT '{}',
    quiz           jsonb,
    moderator_id   uuid REFERENCES users(id) ON DELETE SET NULL,
    moderator_note text,
    card_id        text REFERENCES cards(id) ON DELETE SET NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    decided_at     timestamptz
);
CREATE INDEX contributions_pending_idx ON contributions (created_at) WHERE status = 'pending';

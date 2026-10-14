-- Full summary posts: one post for a whole book or topic, read part by part.
-- Every part is an existing card. Book summaries are built from each source's
-- cards at seed time; topic summaries come from content/summaries/*.json and
-- draw their cards from several sources.

CREATE TABLE summaries (
    id           text PRIMARY KEY,
    kind         text NOT NULL CHECK (kind IN ('book', 'topic')),
    title        text NOT NULL,
    description  text NOT NULL DEFAULT '',
    topic        text NOT NULL REFERENCES topics(slug),
    source_id    text REFERENCES sources(id),       -- book summaries only
    source_ids   text[] NOT NULL DEFAULT '{}',      -- every source a part comes from
    authors      text[] NOT NULL DEFAULT '{}',
    card_ids     text[] NOT NULL,
    words        int NOT NULL DEFAULT 0,
    status       text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'hidden')),
    published_at timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX summaries_topic_idx ON summaries (topic) WHERE status = 'published';
CREATE INDEX summaries_source_idx ON summaries (source_id) WHERE source_id IS NOT NULL;

-- Where a reader is in a summary, so they can pick up where they stopped.
CREATE TABLE summary_progress (
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    summary_id  text NOT NULL REFERENCES summaries(id) ON DELETE CASCADE,
    position    int NOT NULL DEFAULT 0 CHECK (position >= 0),
    started_at  timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, summary_id)
);

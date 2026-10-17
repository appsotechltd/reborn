-- Subjects: short courses of guides followed one after the other (for example
-- Communication Clarity under Life Guides). Each step is a guide's book
-- summary, so a reader's progress through a subject is their summary progress.
-- Built from content/subjects/*.json at seed time.

CREATE TABLE subjects (
    id          text PRIMARY KEY,
    title       text NOT NULL,
    description text NOT NULL DEFAULT '',
    topics      text[] NOT NULL,   -- categories that list it, main one first
    summary_ids text[] NOT NULL,   -- the guides' summaries, in reading order
    status      text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'hidden')),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX subjects_topics_idx ON subjects USING gin (topics);

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { ErrorNote, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS } from "@/lib/content";
import { AUDIENCES } from "@/lib/studio";
import { useLoad } from "@/lib/use-load";
import type { Audience, Card, MemberCategory, NewMemberCard } from "@/lib/types";

export const TITLE_MAX = 120;
export const BODY_MAX = 1500;
export const APPLY_MAX = 400;

export function NewCardView() {
  const router = useRouter();
  return (
    <div className="mx-auto max-w-read">
      <p>
        <Link href="/me/cards" className="link text-sm">
          ← My cards
        </Link>
      </p>
      <h1 className="mt-4 font-serif text-4xl font-semibold tracking-tight">Write a card</h1>
      <p className="mt-2 text-muted">One idea, in your own words. After saving you can add a picture, audio or a video.</p>
      <div className="mt-8">
        <RequireAuth message="Sign in to write your own cards.">
          <CardEditor onSaved={(c) => router.push(`/me/cards/${encodeURIComponent(c.id)}`)} />
        </RequireAuth>
      </div>
    </div>
  );
}

/** The card's words, topic, category and audience. With `card`, edits it; without, creates one. */
export function CardEditor({ card, onSaved }: { card?: Card; onSaved: (card: Card) => void }) {
  const { api, token } = useAuth();
  const topicsLoader = useCallback(() => api.topics().then((r) => r.topics), [api]);
  const topics = useLoad(topicsLoader).data;
  const catLoader = useCallback(() => api.myCategories().then((r) => r.categories), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const categories = useLoad<MemberCategory[]>(catLoader).data ?? [];

  const [title, setTitle] = useState(card?.title ?? "");
  const [body, setBody] = useState(card?.body ?? "");
  const [applyIt, setApplyIt] = useState(card?.apply_it ?? "");
  const [topic, setTopic] = useState(card?.topic ?? "");
  const [categoryId, setCategoryId] = useState(card?.category?.id ?? "");
  const hidden = card?.visibility === "hidden";
  const [audience, setAudience] = useState<Audience>(
    (AUDIENCES.find((a) => a.id === card?.visibility)?.id ?? "everyone") as Audience,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSaved(false);
    const fields: NewMemberCard = {
      title: title.trim(),
      body: body.trim(),
      apply_it: applyIt.trim(),
      topic,
      category_id: categoryId,
    };
    // A card taken down after reports stays hidden; its audience can't be changed until a moderator restores it.
    if (!hidden) fields.audience = audience;
    if (!card && !fields.category_id) delete fields.category_id;
    setBusy(true);
    try {
      const res = card ? await api.updateMyCard(card.id, fields) : await api.createMyCard(fields);
      setSaved(true);
      onSaved(res);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save the card.");
    } finally {
      setBusy(false);
    }
  }

  const topicList = topics?.length ? topics : TOPICS;

  return (
    <form onSubmit={submit} className="panel space-y-4 p-5" aria-label={card ? "Edit card" : "New card"}>
      <div>
        <label htmlFor="card-title" className="label">
          Title
        </label>
        <input
          id="card-title"
          className="field"
          required
          maxLength={TITLE_MAX}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          aria-describedby="card-title-hint"
        />
        <p id="card-title-hint" className="hint">
          {title.length}/{TITLE_MAX}
        </p>
      </div>
      <div>
        <label htmlFor="card-body" className="label">
          The idea
        </label>
        <textarea
          id="card-body"
          className="field min-h-48 resize-y text-lg leading-relaxed"
          required
          maxLength={BODY_MAX}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          aria-describedby="card-body-hint"
        />
        <p id="card-body-hint" className="hint">
          Leave a blank line between paragraphs. {body.length}/{BODY_MAX}
        </p>
      </div>
      <div>
        <label htmlFor="card-apply" className="label">
          Apply it <span className="font-normal text-muted">(optional)</span>
        </label>
        <textarea
          id="card-apply"
          className="field min-h-20 resize-y"
          maxLength={APPLY_MAX}
          value={applyIt}
          onChange={(e) => setApplyIt(e.target.value)}
          aria-describedby="card-apply-hint"
        />
        <p id="card-apply-hint" className="hint">
          One small action or question. {applyIt.length}/{APPLY_MAX}
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="card-topic" className="label">
            Topic
          </label>
          <select id="card-topic" className="field" required value={topic} onChange={(e) => setTopic(e.target.value)}>
            <option value="" disabled>
              Choose a topic
            </option>
            {topicList.map((t) => (
              <option key={t.slug} value={t.slug}>
                {t.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="card-category" className="label">
            Category <span className="font-normal text-muted">(optional)</span>
          </label>
          <select id="card-category" className="field" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">None</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <p className="hint">
            <Link href="/me/cards#categories-title" className="link">
              Manage categories
            </Link>
          </p>
        </div>
      </div>
      <fieldset>
        <legend className="label">Who can see it</legend>
        {hidden ? (
          <p className="text-sm text-bad">Hidden after reports. A moderator will look at it.</p>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {AUDIENCES.map((a) => (
              <label
                key={a.id}
                className={`flex cursor-pointer items-start gap-2 rounded-xl border px-3 py-2 ${audience === a.id ? "border-accent bg-accent-soft" : "border-line"}`}
              >
                <input
                  type="radio"
                  name="audience"
                  value={a.id}
                  checked={audience === a.id}
                  onChange={() => setAudience(a.id)}
                  className="mt-1 size-4"
                />
                <span>
                  <span className="font-semibold">{a.label}</span>
                  <span className="block text-sm text-muted">{a.hint}</span>
                </span>
              </label>
            ))}
          </div>
        )}
      </fieldset>
      <ErrorNote error={error} />
      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" className="btn btn-primary" disabled={busy || !title.trim() || !body.trim() || !topic}>
          {busy ? "Saving…" : card ? "Save changes" : "Save card"}
        </button>
        {saved && card ? (
          <span role="status" className="text-sm font-semibold text-ok">
            Saved ✓
          </span>
        ) : null}
      </div>
    </form>
  );
}

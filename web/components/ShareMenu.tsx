"use client";

import { useState } from "react";
import { useAuth, useHydrated } from "@/lib/auth";
import { formatCount, ideaPath, shareTargets } from "@/lib/social";
import { useSiteUrl } from "@/lib/site-url";
import type { ShareChannel } from "@/lib/types";
import { Icon } from "./Icon";
import { Modal } from "./Modal";

/**
 * Share anything with a public page (an idea, book, author, topic, summary, stash): network links,
 * Copy link and (when the browser has it) the system share sheet, which reaches Instagram and the
 * rest on phones. Only idea shares (`postId`) are counted.
 */
export function ShareMenu({
  postId,
  path,
  title,
  what = "idea",
  label = false,
  count,
  onShared,
}: {
  /** The idea being shared; its share is counted. */
  postId?: string;
  /** Site path to share when it isn't an idea, e.g. `/sources/meditations`. */
  path?: string;
  title: string;
  /** What is being shared, for the dialog heading ("Share this book"). */
  what?: string;
  /** Show a "Share" label next to the icon. */
  label?: boolean;
  /** Times shared, shown next to the icon. */
  count?: number;
  onShared?: () => void;
}) {
  const { api } = useAuth();
  const site = useSiteUrl();
  const hydrated = useHydrated();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const url = `${site}${path ?? (postId ? ideaPath(postId) : "/")}`;
  const canNativeShare = hydrated && typeof navigator !== "undefined" && typeof navigator.share === "function";
  const key = (postId ?? path ?? "page").replace(/[^a-zA-Z0-9_-]/g, "-");
  const titleId = `share-${key}-title`;

  function record(channel: ShareChannel) {
    onShared?.();
    if (!postId) return;
    api.share(postId, channel).catch(() => {
      // Counting is best effort; never get in the way of the share itself.
    });
  }

  async function copy() {
    setError(null);
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      record("copy_link");
      window.setTimeout(() => setCopied(false), 2500);
    } catch {
      setError("Couldn't copy automatically. Select the link above and copy it.");
    }
  }

  async function nativeShare() {
    try {
      await navigator.share({ title, text: title, url });
      record("native");
      setOpen(false);
    } catch (err) {
      if (!(err instanceof DOMException && err.name === "AbortError")) setError("Couldn't open the share sheet.");
    }
  }

  return (
    <>
      <button
        type="button"
        className={label ? "btn btn-small" : "btn btn-small btn-ghost gap-1.5 px-2.5 text-muted hover:text-fg"}
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <Icon name="share" className={label ? "size-4" : undefined} />
        <span className={label ? undefined : "sr-only"}>Share</span>
        {count !== undefined ? (
          <>
            <span aria-hidden="true">{formatCount(count)}</span>
            <span className="sr-only">, shared {count} {count === 1 ? "time" : "times"}</span>
          </>
        ) : null}
      </button>
      <Modal open={open} onClose={() => setOpen(false)} titleId={titleId}>
        <h2 id={titleId} className="font-serif text-xl font-semibold">
          Share this {what}
        </h2>
        <p className="mt-1 text-sm text-muted">“{title}”</p>
        <label htmlFor={`share-${key}-url`} className="sr-only">
          Link to this {what}
        </label>
        <input
          id={`share-${key}-url`}
          className="field mt-4 text-sm"
          readOnly
          value={url}
          onFocus={(e) => e.currentTarget.select()}
        />
        <ul className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
          {shareTargets(url, title).map((t) => (
            <li key={t.channel}>
              <a
                href={t.href}
                target={t.channel === "email" ? undefined : "_blank"}
                rel="noopener noreferrer"
                className="btn btn-small w-full"
                onClick={() => record(t.channel)}
              >
                {t.label}
                {t.channel !== "email" ? <span className="sr-only"> (opens in a new tab)</span> : null}
              </a>
            </li>
          ))}
          <li>
            <button type="button" className="btn btn-small w-full" onClick={copy}>
              {copied ? "Copied ✓" : "Copy link"}
            </button>
          </li>
          {canNativeShare ? (
            <li>
              <button type="button" className="btn btn-small w-full" onClick={nativeShare}>
                More apps…
              </button>
            </li>
          ) : null}
        </ul>
        <p className="hint mt-3">For Instagram, copy the link{canNativeShare ? " or use More apps" : ""}.</p>
        <p role="status" className="sr-only">
          {copied ? "Link copied" : ""}
        </p>
        {error ? (
          <p role="alert" className="mt-3 text-sm text-bad">
            {error}
          </p>
        ) : null}
        <div className="mt-5 text-right">
          <button type="button" className="btn" onClick={() => setOpen(false)}>
            Done
          </button>
        </div>
      </Modal>
    </>
  );
}

"use client";

import { useState } from "react";
import { useAuth, useHydrated } from "@/lib/auth";
import { browserApiUrl } from "@/lib/config";
import { formatCount, ideaPath, shareTargets } from "@/lib/social";
import { useSiteUrl } from "@/lib/site-url";
import type { Explainer, ShareChannel } from "@/lib/types";
import { Icon } from "./Icon";
import { Modal } from "./Modal";

/**
 * Share anything with a public page (an idea, book, author, topic, summary, stash): network links,
 * Copy link and (when the browser has it) the system share sheet, which reaches Instagram and the
 * rest on phones. Only idea shares (`postId`) are counted.
 *
 * An idea with a video also offers the video itself, in the shape that suits where it goes: tall
 * (9:16) for Status, Reels, Shorts and TikTok, wide (16:9) for YouTube, Facebook, X and LinkedIn.
 * Phones put the file in the share sheet; elsewhere it downloads. Link shares already carry the
 * page's preview.
 */

type Shape = "tall" | "wide";
export function ShareMenu({
  postId,
  path,
  title,
  what = "idea",
  label = false,
  count,
  onShared,
  video,
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
  /** The idea's video, offered as a file in each shape it has. */
  video?: { cardId: string; explainer: Explainer } | null;
}) {
  const { api } = useAuth();
  const site = useSiteUrl();
  const hydrated = useHydrated();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fetching, setFetching] = useState<Shape | null>(null);
  // A video fetched for the share sheet, waiting for a tap when the browser wanted a fresh one.
  const [ready, setReady] = useState<{ shape: Shape; file: File } | null>(null);
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

  function videoUrl(shape: Shape) {
    return `${browserApiUrl()}/v1/cards/${encodeURIComponent(video!.cardId)}/video?shape=${shape}`;
  }

  async function shareFile(file: File, shape: Shape) {
    try {
      await navigator.share({ files: [file], title, text: `${title} ${url}` });
      record("native");
      setReady(null);
    } catch (err) {
      if (err instanceof DOMException && err.name === "NotAllowedError") return setReady({ shape, file });
      if (!(err instanceof DOMException && err.name === "AbortError")) setError("Couldn't open the share sheet.");
    }
  }

  async function shareVideo(shape: Shape) {
    setError(null);
    setReady(null);
    const href = videoUrl(shape);
    // Phones share the file itself; elsewhere the video downloads, ready to upload.
    if (canNativeShare && typeof navigator.canShare === "function") {
      setFetching(shape);
      try {
        const res = await fetch(href);
        if (!res.ok) throw new Error(String(res.status));
        const file = new File([await res.blob()], `reborn-${video!.cardId}-${shape}.mp4`, { type: "video/mp4" });
        if (navigator.canShare({ files: [file] })) return await shareFile(file, shape);
      } catch {
        // Fall through to the download.
      } finally {
        setFetching(null);
      }
    }
    const a = document.createElement("a");
    a.href = href;
    a.download = `reborn-${video!.cardId}-${shape}.mp4`;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  const shapes: { shape: Shape; label: string; fits: string }[] = video
    ? [
        { shape: "tall", label: "Tall video", fits: "Status, Reels, Shorts, TikTok" },
        ...(video.explainer.landscape ? [{ shape: "wide" as const, label: "Wide video", fits: "YouTube, Facebook, X, LinkedIn" }] : []),
      ]
    : [];

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
        {shapes.length ? (
          <section className="mt-5" aria-labelledby={`share-${key}-video`}>
            <h3 id={`share-${key}-video`} className="text-sm font-semibold">
              Share the video
            </h3>
            <p className="hint mt-0.5">Pick the shape that fits where it&apos;s going.</p>
            <ul className="mt-2 grid gap-2 sm:grid-cols-2">
              {shapes.map((s) => (
                <li key={s.shape}>
                  <button
                    type="button"
                    className="btn btn-small h-auto w-full flex-col gap-0 py-2"
                    data-shape={s.shape}
                    disabled={fetching !== null}
                    onClick={() => (ready?.shape === s.shape ? shareFile(ready.file, s.shape) : shareVideo(s.shape))}
                  >
                    <span>{fetching === s.shape ? "Getting the video…" : ready?.shape === s.shape ? `Share the ${s.label.toLowerCase()}` : s.label}</span>
                    <span className="text-xs font-normal text-muted">{s.fits}</span>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
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

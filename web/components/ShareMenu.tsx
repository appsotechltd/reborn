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
 * Phones put the file in the share sheet; elsewhere it downloads. An idea with a picture (its
 * image post or card picture) puts the picture in the share sheet with the link ("More apps…").
 * Link shares already carry the page's own picture or video poster as their preview.
 */

type Shape = "tall" | "wide" | "picture";
export function ShareMenu({
  postId,
  path,
  title,
  what = "idea",
  label = false,
  count,
  onShared,
  video,
  picture,
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
  /** The idea whose picture is offered as a file (an image post or card picture). */
  picture?: { cardId: string } | null;
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
    setError(null);
    if (picture) {
      const done = await sharePicture();
      if (done === "shared") setOpen(false);
      if (done !== "none") return;
    }
    try {
      await navigator.share({ title, text: title, url });
      record("native");
      setOpen(false);
    } catch (err) {
      if (!(err instanceof DOMException && err.name === "AbortError")) setError("Couldn't open the share sheet.");
    }
  }

  // The API hands out the files: the media bucket sends no CORS headers.
  function fileUrl(shape: Shape) {
    if (shape === "picture") return `${browserApiUrl()}/v1/cards/${encodeURIComponent(picture!.cardId)}/picture`;
    return `${browserApiUrl()}/v1/cards/${encodeURIComponent(video!.cardId)}/video?shape=${shape}`;
  }

  function fileName(shape: Shape, type = "") {
    if (shape !== "picture") return `reborn-${video!.cardId}-${shape}.mp4`;
    const ext = type.includes("png") ? "png" : type.includes("webp") ? "webp" : "jpg";
    return `reborn-${picture!.cardId}.${ext}`;
  }

  /** Shares [file] with the link. False only when the browser wants a fresh tap first. */
  async function shareFile(file: File, shape: Shape): Promise<boolean> {
    try {
      await navigator.share({ files: [file], title, text: `${title} ${url}` });
      record("native");
      setReady(null);
    } catch (err) {
      if (err instanceof DOMException && err.name === "NotAllowedError") {
        setReady({ shape, file });
        return false;
      }
      if (!(err instanceof DOMException && err.name === "AbortError")) setError("Couldn't open the share sheet.");
    }
    return true;
  }

  /**
   * Puts the picture in the share sheet with the link. "none" when it couldn't (no file sharing,
   * or the picture couldn't be fetched), so the link goes alone; "ready" when the browser wants a
   * fresh tap after the fetch, which the More apps button then offers.
   */
  async function sharePicture(): Promise<"shared" | "ready" | "none"> {
    const send = async (file: File) => ((await shareFile(file, "picture")) ? "shared" : "ready");
    if (ready?.shape === "picture") return send(ready.file);
    if (typeof navigator.canShare !== "function") return "none";
    setFetching("picture");
    let file: File;
    try {
      const res = await fetch(fileUrl("picture"));
      if (!res.ok) return "none";
      const blob = await res.blob();
      const type = blob.type || "image/jpeg";
      file = new File([blob], fileName("picture", type), { type });
      if (!navigator.canShare({ files: [file] })) return "none";
    } catch {
      return "none";
    } finally {
      setFetching(null);
    }
    return send(file);
  }

  async function shareMedia(shape: Shape) {
    setError(null);
    setReady(null);
    const href = fileUrl(shape);
    // Phones share the file itself; elsewhere it downloads, ready to upload.
    if (canNativeShare && typeof navigator.canShare === "function") {
      setFetching(shape);
      try {
        const res = await fetch(href);
        if (!res.ok) throw new Error(String(res.status));
        const blob = await res.blob();
        const type = shape === "picture" ? blob.type || "image/jpeg" : "video/mp4";
        const file = new File([blob], fileName(shape, type), { type });
        if (navigator.canShare({ files: [file] })) return await shareFile(file, shape);
      } catch {
        // Fall through to the download.
      } finally {
        setFetching(null);
      }
    }
    const a = document.createElement("a");
    a.href = href;
    a.download = fileName(shape);
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
              <button type="button" className="btn btn-small w-full" onClick={nativeShare} disabled={fetching !== null}>
                {fetching === "picture" ? "Getting the picture…" : ready?.shape === "picture" ? "Share with picture" : "More apps…"}
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
                    onClick={() => (ready?.shape === s.shape ? shareFile(ready.file, s.shape) : shareMedia(s.shape))}
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

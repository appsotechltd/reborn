"use client";

import Link from "next/link";
import { useState } from "react";
import { useAuth } from "@/lib/auth";
import { embedSnippet } from "@/lib/social";
import { useSiteUrl } from "@/lib/site-url";
import { Modal } from "./Modal";

/** "Embed" dialog with a copyable iframe snippet for /embed/ideas/[id]. */
export function EmbedButton({ postId, title }: { postId: string; title: string }) {
  const { api } = useAuth();
  const site = useSiteUrl();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const snippet = embedSnippet(site, postId, title);
  const titleId = `embed-${postId}-title`;

  async function copy() {
    setError(null);
    try {
      await navigator.clipboard.writeText(snippet);
      setCopied(true);
      api.share(postId, "embed").catch(() => {});
      window.setTimeout(() => setCopied(false), 2500);
    } catch {
      setError("Couldn't copy automatically. Select the code and copy it.");
    }
  }

  return (
    <>
      <button type="button" className="btn btn-small btn-ghost" aria-haspopup="dialog" onClick={() => setOpen(true)}>
        <span aria-hidden="true">&lt;/&gt;</span> <span data-action-label>Embed</span>
      </button>
      <Modal open={open} onClose={() => setOpen(false)} titleId={titleId}>
        <h2 id={titleId} className="font-serif text-xl font-semibold">
          Embed this idea
        </h2>
        <p className="mt-1 text-sm text-muted">
          Paste this code into your site or blog. The card keeps its credit, licence and a link back to Reborn.
        </p>
        <label htmlFor={`embed-${postId}-code`} className="label mt-4">
          Embed code
        </label>
        <textarea
          id={`embed-${postId}-code`}
          className="field min-h-28 font-mono text-xs"
          readOnly
          value={snippet}
          onFocus={(e) => e.currentTarget.select()}
        />
        <p role="status" className="sr-only">
          {copied ? "Embed code copied" : ""}
        </p>
        {error ? (
          <p role="alert" className="mt-3 text-sm text-bad">
            {error}
          </p>
        ) : null}
        <div className="mt-5 flex flex-wrap justify-between gap-2">
          <Link href={`/embed/ideas/${postId}`} target="_blank" rel="noopener noreferrer" className="link self-center text-sm">
            Preview<span className="sr-only"> (opens in a new tab)</span>
          </Link>
          <span className="flex gap-2">
            <button type="button" className="btn btn-primary" onClick={copy}>
              {copied ? "Copied ✓" : "Copy code"}
            </button>
            <button type="button" className="btn" onClick={() => setOpen(false)}>
              Done
            </button>
          </span>
        </div>
      </Modal>
    </>
  );
}

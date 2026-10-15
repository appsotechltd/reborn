"use client";

import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { Modal } from "./Modal";
import { useSignInRedirect } from "./SignInPrompt";

/**
 * "⋯" next to share on a member's card: report it to the moderators, with an optional reason.
 * Three reports hide a card until a moderator looks. Library cards have no report.
 */
export function ReportButton({ postId, title }: { postId: string; title: string }) {
  const { user, api } = useAuth();
  const toSignIn = useSignInRedirect();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const titleId = `report-${postId}-title`;

  function show() {
    if (!user) return toSignIn();
    setError(null);
    setOpen(true);
  }

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.reportPost(postId, reason.trim() || undefined);
      setOpen(false);
      setReason("");
      setDone(true);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't send the report. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <button
        type="button"
        className="btn btn-small btn-ghost px-2.5 text-muted hover:text-fg"
        aria-haspopup="dialog"
        onClick={show}
        disabled={done}
      >
        <span aria-hidden="true">⋯</span>
        <span className="sr-only">Report this card</span>
      </button>
      {done ? (
        <span role="status" className="text-sm text-muted">
          Thanks, we&apos;ll take a look
        </span>
      ) : null}
      <Modal open={open} onClose={() => setOpen(false)} titleId={titleId}>
        <form onSubmit={send}>
          <h2 id={titleId} className="font-serif text-xl font-semibold">
            Report this card
          </h2>
          <p className="mt-1 text-sm text-muted">“{title}” will be checked by a moderator.</p>
          <label htmlFor={`${titleId}-reason`} className="label mt-4">
            Why? <span className="font-normal text-muted">(optional)</span>
          </label>
          <textarea
            id={`${titleId}-reason`}
            className="field min-h-20"
            maxLength={300}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
          {error ? (
            <p role="alert" className="mt-3 text-sm text-bad">
              {error}
            </p>
          ) : null}
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" className="btn" onClick={() => setOpen(false)}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={busy}>
              {busy ? "Sending…" : "Report"}
            </button>
          </div>
        </form>
      </Modal>
    </>
  );
}

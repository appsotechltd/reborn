"use client";

import { useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { BlockKind } from "@/lib/types";

/**
 * "⋯" menu to mute or block someone (or undo it). Reads the current state from
 * GET /v1/me/blocks when opened. Renders nothing for yourself or signed-out visitors.
 */
export function BlockMenu({
  userId,
  name,
  onChange,
  align = "right",
}: {
  userId: string;
  name: string;
  onChange?: (kind: BlockKind | null) => void;
  align?: "left" | "right";
}) {
  const { user, api } = useAuth();
  const [open, setOpen] = useState(false);
  const [state, setState] = useState<BlockKind | null | undefined>(undefined);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const wrap = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  if (!user || user.id === userId) return null;

  async function toggleOpen() {
    const next = !open;
    setOpen(next);
    setError(null);
    if (next && state === undefined) {
      try {
        const r = await api.blocks();
        setState(r.blocks.find((b) => b.id === userId)?.kind ?? null);
      } catch {
        setState(null);
      }
    }
  }

  async function apply(kind: BlockKind | null) {
    setBusy(true);
    setError(null);
    try {
      await api.setBlock(userId, kind);
      setState(kind);
      setOpen(false);
      setDone(kind === "block" ? `Blocked ${name}.` : kind === "mute" ? `Muted ${name}.` : `${name} can be seen again.`);
      onChange?.(kind);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't update. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div ref={wrap} className="relative inline-block">
      <button
        type="button"
        className="inline-flex items-center justify-center rounded-full px-2 text-muted hover:bg-surface-2 hover:text-fg pointer-coarse:-my-2.5 pointer-coarse:min-h-11 pointer-coarse:min-w-11"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={toggleOpen}
      >
        <span aria-hidden="true">⋯</span>
        <span className="sr-only">More options for {name}</span>
      </button>
      {open ? (
        <div
          role="menu"
          className={`absolute z-20 mt-1 w-48 rounded-xl border border-line bg-surface p-1 text-left text-sm shadow-lg ${
            align === "right" ? "right-0" : "left-0"
          }`}
        >
          {state === undefined ? (
            <p role="status" className="px-3 py-2 text-muted">Loading…</p>
          ) : (
            <>
              {state === "mute" ? (
                <MenuItem disabled={busy} onClick={() => apply(null)}>Unmute {name}</MenuItem>
              ) : state !== "block" ? (
                <MenuItem disabled={busy} onClick={() => apply("mute")}>Mute {name}</MenuItem>
              ) : null}
              {state === "block" ? (
                <MenuItem disabled={busy} onClick={() => apply(null)}>Unblock {name}</MenuItem>
              ) : (
                <MenuItem disabled={busy} onClick={() => apply("block")} danger>Block {name}</MenuItem>
              )}
            </>
          )}
          {error ? <p role="alert" className="px-3 py-2 text-bad">{error}</p> : null}
        </div>
      ) : null}
      {done ? (
        <span role="status" className="sr-only">
          {done}
        </span>
      ) : null}
    </div>
  );
}

function MenuItem({
  children,
  onClick,
  disabled,
  danger,
}: {
  children: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
  danger?: boolean;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      onClick={onClick}
      className={`block w-full truncate rounded-lg px-3 py-2 text-left hover:bg-surface-2 ${danger ? "text-bad" : ""}`}
    >
      {children}
    </button>
  );
}

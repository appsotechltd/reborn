"use client";

import { useEffect, useState } from "react";
import { useHydrated } from "@/lib/auth";

/** Reads text aloud with the browser's Web Speech API. Hidden when unsupported. */
export function ListenButton({ text, lang = "en" }: { text: string; lang?: string }) {
  const hydrated = useHydrated();
  const [speaking, setSpeaking] = useState(false);

  useEffect(() => {
    return () => {
      if (typeof window !== "undefined" && "speechSynthesis" in window) window.speechSynthesis.cancel();
    };
  }, []);

  if (!hydrated || typeof window === "undefined" || !("speechSynthesis" in window)) return null;

  function toggle() {
    const synth = window.speechSynthesis;
    if (speaking) {
      synth.cancel();
      setSpeaking(false);
      return;
    }
    synth.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = lang;
    u.rate = 0.95;
    u.onend = () => setSpeaking(false);
    u.onerror = () => setSpeaking(false);
    setSpeaking(true);
    synth.speak(u);
  }

  return (
    <button type="button" className="btn btn-small" onClick={toggle} aria-pressed={speaking}>
      <span aria-hidden="true">{speaking ? "■" : "▶"}</span>
      {speaking ? "Stop" : "Listen"}
    </button>
  );
}

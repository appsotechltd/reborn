import { formatMoney } from "./social";
import type { AIRate, AIWallet, UnitPack } from "./types";

/** "1 unit" / "12 units". */
export function units(n: number): string {
  return `${n.toLocaleString("en")} ${n === 1 ? "unit" : "units"}`;
}

/** "Resets 1 Nov". */
export function resetLabel(w: AIWallet): string {
  const d = new Date(w.resets_at);
  return `Resets ${d.toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" })}`;
}

/** One line on what's left: "180 of 250 monthly units left, plus 600 top-up units". */
export function walletSummary(w: AIWallet): string {
  const monthly = w.monthly_units > 0 ? `${w.allowance_left.toLocaleString("en")} of ${units(w.monthly_units)} left this month` : "";
  const topup = w.topup_units > 0 ? `${units(w.topup_units)} from top-ups` : "";
  if (monthly && topup) return `${monthly}, plus ${topup}`;
  return monthly || topup || "No AI units left";
}

/** Share of the monthly allowance still unused, 0..1. */
export function allowanceShare(w: AIWallet): number {
  return w.monthly_units > 0 ? Math.max(0, Math.min(1, w.allowance_left / w.monthly_units)) : 0;
}

const RATE_LABELS: Record<string, string> = {
  text: "Each reply",
  chart: "A chart or graph",
  voice: "Voice",
  sketch: "A sketch",
  illustration: "An illustration",
  picture: "A photo-like picture",
};

export function rateLabel(r: AIRate): string {
  return RATE_LABELS[r.kind] ?? r.kind;
}

export function rateText(r: AIRate): string {
  return r.kind === "voice" ? `${units(r.units)} per 30 spoken words` : units(r.units);
}

export function packPrice(p: UnitPack): string {
  return formatMoney(p.amount_cents, p.currency);
}

/** Price per 100 units, to compare packs: "$1.20 per 100". */
export function packRate(p: UnitPack): string {
  return `${formatMoney(Math.round((p.amount_cents * 100) / p.units), p.currency)} per 100`;
}

/** Picks a recording format the browser supports, with the file extension the server accepts. */
export function recordingFormat(isSupported: (type: string) => boolean): { mimeType: string; ext: string } | null {
  for (const [mimeType, ext] of [
    ["audio/webm;codecs=opus", "webm"],
    ["audio/webm", "webm"],
    ["audio/mp4", "m4a"],
    ["audio/ogg;codecs=opus", "ogg"],
  ] as const) {
    if (isSupported(mimeType)) return { mimeType, ext };
  }
  return null;
}

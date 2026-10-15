import { visibilityLabel } from "@/lib/studio";

/** Who can see one of my cards: Everyone, Followers, Subscribers, Only me, or Hidden after reports. */
export function VisibilityBadge({ visibility }: { visibility?: string | null }) {
  const hidden = visibility === "hidden";
  return (
    <span
      className={`inline-flex shrink-0 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${
        hidden ? "border-bad text-bad" : visibility === "everyone" || !visibility ? "border-line text-muted" : "border-accent text-accent-text"
      }`}
      data-testid="visibility"
    >
      {visibilityLabel(visibility)}
    </span>
  );
}

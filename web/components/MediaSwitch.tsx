import type { MediaFilter } from "@/lib/media-filter";
import { Icon } from "./Icon";

const LABELS: Record<MediaFilter, string> = { all: "All", videos: "Videos", images: "Images" };

/**
 * The All / Videos / Images pills (a book's or an author's cards, and the timeline). `options`
 * lists the ones to offer, each with an optional count shown after its name.
 */
export function MediaSwitch({
  options,
  selected,
  onSelect,
  className = "",
  small = false,
}: {
  options: { id: MediaFilter; count?: number }[];
  selected: MediaFilter;
  onSelect: (filter: MediaFilter) => void;
  className?: string;
  /** The timeline's compact row. */
  small?: boolean;
}) {
  return (
    <div role="group" aria-label="Show" className={`inline-flex rounded-full border border-line p-1 ${className}`}>
      {options.map(({ id, count }) => {
        const on = selected === id;
        return (
          <button
            key={id}
            type="button"
            aria-pressed={on}
            onClick={() => onSelect(id)}
            className={`inline-flex items-center gap-1.5 rounded-full text-sm ${
              small ? "min-h-8 px-3 pointer-coarse:min-h-9" : "min-h-9 px-4 pointer-coarse:min-h-11"
            } ${on ? "bg-chip-on font-semibold text-chip-on-fg" : "text-muted hover:text-fg"}`}
          >
            {id === "videos" ? <Icon name="play" className="size-4" /> : null}
            {id === "images" ? <Icon name="image" className="size-4" /> : null}
            {LABELS[id]}
            {count === undefined ? null : (
              <>
                {" "}
                <span className={on ? undefined : "text-muted"}>({count})</span>
              </>
            )}
          </button>
        );
      })}
    </div>
  );
}

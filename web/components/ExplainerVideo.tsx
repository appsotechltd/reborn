import { mediaUrl } from "@/lib/config";
import type { Card } from "@/lib/types";

/**
 * The card's animated explainer. The credit, licence and any health note are
 * burned into the video itself, and the card's own credit stays on the page.
 * Nothing downloads until the reader presses play.
 */
export function ExplainerVideo({ card }: { card: Card }) {
  const e = card.explainer;
  if (!e) return null;
  const seconds = Math.round(e.duration_s);
  return (
    <figure className="mt-6" data-testid="explainer">
      <video
        controls
        playsInline
        preload="none"
        crossOrigin="anonymous"
        poster={mediaUrl(e.poster_url)}
        width={e.width}
        height={e.height}
        className="mx-auto h-auto w-full max-w-[22rem] rounded-2xl border border-line bg-surface-2"
        aria-label={`Animated explainer: ${card.title}`}
      >
        <source src={mediaUrl(e.video_url)} type="video/mp4" />
        {e.captions_url ? <track kind="captions" srcLang="en" label="English" src={mediaUrl(e.captions_url)} /> : null}
      </video>
      <figcaption className="mt-2 text-center text-sm text-muted">
        {e.kind === "film" ? "Short film" : "Animated explainer"} · {seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 6) / 10} min`}
      </figcaption>
    </figure>
  );
}

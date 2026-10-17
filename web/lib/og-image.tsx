import { ImageResponse } from "next/og";
import { excerpt, formatAuthors, TOPICS } from "./content";
import { SITE_NAME, SITE_TAGLINE } from "./config";
import { getAuthor, getCard, getSource, getSubject, getSummary, getTopics, loadOr } from "./server-api";
import { asJpeg, mediaPreviewImage } from "./og-media";
import { cardPreviewMedia, coverPreviewMedia, type PreviewMedia } from "./preview-media";
import { subjectMeta } from "./subjects";
import { coverageLabel, summaryByline } from "./summaries";

export const OG_SIZE = { width: 1200, height: 630 };
export const OG_ALT = "Reborn: big ideas from great books, one minute at a time";

interface Preview {
  /** Small label above the title ("Book", "Author", "Topic"). */
  eyebrow?: string;
  title: string;
  text: string;
  footer?: string;
}

/**
 * The shared link-preview layout (WhatsApp, Facebook, X, LinkedIn, iMessage...): eyebrow, title,
 * a short text and a footer line, in the Candlelight dark palette (design/candlelight.md).
 * OG images are fixed images, not themed.
 */
export function previewImage({ eyebrow, title, text, footer }: Preview): ImageResponse {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "64px 72px",
          background: "#14110e",
          color: "#f2e8d8",
          borderTop: "16px solid #e9a23b",
          fontFamily: "serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", alignItems: "baseline", fontSize: 30, fontWeight: 700, letterSpacing: 1 }}>
            {SITE_NAME}
            <span style={{ color: "#e9a23b" }}>.</span>
            {eyebrow ? (
              <span style={{ marginLeft: 20, fontSize: 24, fontWeight: 400, color: "#e9a23b", letterSpacing: 2 }}>
                {eyebrow.toUpperCase()}
              </span>
            ) : null}
          </div>
          <div
            style={{
              display: "flex",
              marginTop: 28,
              fontSize: title.length > 70 ? 54 : 64,
              fontWeight: 700,
              lineHeight: 1.12,
            }}
          >
            {excerpt(title, 110)}
          </div>
          <div style={{ display: "flex", marginTop: 28, fontSize: 30, lineHeight: 1.4, color: "#d9cdba" }}>
            {excerpt(text, 190)}
          </div>
        </div>
        <div
          style={{
            display: "flex",
            borderTop: "2px solid #3a3027",
            paddingTop: 20,
            fontSize: 22,
            color: "#a89a86",
          }}
        >
          {footer ? excerpt(footer, 120) : SITE_TAGLINE}
        </div>
      </div>
    ),
    OG_SIZE,
  );
}

/** The site-wide preview, for pages without their own. */
export function siteImage(): ImageResponse {
  return previewImage({
    title: SITE_TAGLINE,
    text: "One-minute idea cards, summaries and guides from great books, thinkers and open sources. Read, listen and save the ideas that help.",
    footer: "Free to read on the web and on Android",
  });
}

/**
 * A JPEG preview: the content's own picture or video poster when it has one, otherwise the drawn
 * text preview. Routes using this declare contentType image/jpeg.
 */
async function withMedia(media: PreviewMedia | null, drawn: () => ImageResponse): Promise<Response> {
  const picture = media ? await mediaPreviewImage(media) : null;
  return picture ?? asJpeg(drawn());
}

/** Link preview for an idea: its picture or video poster, else title, excerpt and credit line. */
export async function ideaImage(id: string): Promise<Response> {
  const { data: card } = await loadOr(() => getCard(id), null);
  if (!card) return asJpeg(siteImage());
  return withMedia(cardPreviewMedia(card), () =>
    previewImage({ title: card.title, text: card.body, footer: card.credit || undefined }),
  );
}

export async function sourceImage(id: string): Promise<ImageResponse> {
  const { data } = await loadOr(() => getSource(id), null);
  if (!data) return siteImage();
  const { source, cards } = data;
  const isBook = source.kind === "book" || source.kind === "textbook";
  return previewImage({
    eyebrow: isBook ? "Book" : source.kind,
    title: source.title,
    text: `by ${formatAuthors(source.authors)}. ${cards.length} one-minute ${cards.length === 1 ? "idea" : "ideas"} to read or listen to.`,
    footer: source.attribution,
  });
}

export async function authorImage(name: string): Promise<ImageResponse> {
  const { data } = await loadOr(() => getAuthor(name), null);
  if (!data) return siteImage();
  const cards = data.card_count ?? data.sources.reduce((n, s) => n + s.card_count, 0);
  const works = data.sources.slice(0, 3).map((s) => s.title);
  return previewImage({
    eyebrow: "Author",
    title: data.name,
    text: `${cards} one-minute ${cards === 1 ? "idea" : "ideas"} from ${data.sources.length} ${data.sources.length === 1 ? "work" : "works"}${works.length ? `, including ${works.join(", ")}` : ""}.`,
  });
}

export async function topicImage(slug: string): Promise<ImageResponse> {
  const { data: topics } = await loadOr(getTopics, TOPICS.map((t) => ({ ...t, card_count: 0 })));
  const topic = topics.find((t) => t.slug === slug);
  if (!topic) return siteImage();
  return previewImage({
    eyebrow: "Topic",
    title: `${topic.name} ideas`,
    text: `${topic.card_count ? `${topic.card_count} one-minute ideas` : "One-minute ideas"} about ${topic.name.toLowerCase()} from great books and open sources, each credited to its source.`,
  });
}

export async function summaryImage(id: string): Promise<Response> {
  const { data } = await loadOr(() => getSummary(id), null);
  if (!data) return asJpeg(siteImage());
  const by = summaryByline(data);
  return withMedia(coverPreviewMedia(data.cover), () => previewImage({
    eyebrow: coverageLabel(data),
    title: data.title,
    text: data.description,
    footer: `${data.part_count} one-minute parts${by ? ` · ${by}` : ""}`,
  }));
}

export async function subjectImage(id: string): Promise<Response> {
  const { data } = await loadOr(() => getSubject(id), null);
  if (!data) return asJpeg(siteImage());
  const first = data.guides.slice(0, 3).map((g) => g.title);
  return withMedia(coverPreviewMedia(data.cover), () => previewImage({
    eyebrow: "Subject",
    title: data.title,
    text: data.description,
    footer: `${subjectMeta(data)}${first.length ? ` · ${first.join(", ")}` : ""}`,
  }));
}

import { formatAuthors } from "@/lib/content";
import { SITE_NAME, siteUrl } from "@/lib/config";
import { getCard, loadOr } from "@/lib/server-api";
import { authorHref, embedSnippet, ideaIdFromUrl } from "@/lib/social";

const WIDTH = 560;
const HEIGHT = 560;

function error(status: number, message: string) {
  return Response.json({ error: message }, { status, headers: { "Access-Control-Allow-Origin": "*" } });
}

/** oEmbed provider: /oembed?url=<idea page>&format=json (https://oembed.com). */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const format = params.get("format") ?? "json";
  if (format !== "json") return error(501, "only format=json is supported");
  const site = siteUrl();
  // Accept URLs on SITE_URL, or on the host this request came in on.
  const id = ideaIdFromUrl(params.get("url") ?? "", site, request.headers.get("host"));
  if (!id) return error(404, "not a Reborn idea URL");

  const { data: card, ok } = await loadOr(() => getCard(id), null);
  if (!ok) return error(503, "temporarily unavailable");
  if (!card) return error(404, "idea not found");

  const maxWidth = Number(params.get("maxwidth")) || Infinity;
  const maxHeight = Number(params.get("maxheight")) || Infinity;
  const width = Math.min(WIDTH, maxWidth);
  const height = Math.min(HEIGHT, maxHeight);
  const html = embedSnippet(site, card.id, card.title)
    .replace(`width="${WIDTH}"`, `width="${width}"`)
    .replace(`height="${HEIGHT}"`, `height="${height}"`);
  const author = card.source.authors[0];

  return Response.json(
    {
      version: "1.0",
      type: "rich",
      provider_name: SITE_NAME,
      provider_url: site,
      title: card.title,
      author_name: formatAuthors(card.source.authors),
      ...(author ? { author_url: `${site}${authorHref(author)}` } : {}),
      html,
      width,
      height,
      cache_age: 86400,
    },
    { headers: { "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=600" } },
  );
}

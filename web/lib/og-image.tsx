import { ImageResponse } from "next/og";
import { excerpt } from "./content";
import { SITE_NAME, SITE_TAGLINE } from "./config";
import { getCard, loadOr } from "./server-api";

export const OG_SIZE = { width: 1200, height: 630 };

/** Link preview for an idea: title, a short excerpt and the credit line. */
export async function ideaImage(id: string): Promise<ImageResponse> {
  const { data: card } = await loadOr(() => getCard(id), null);
  const title = card?.title ?? SITE_NAME;
  const text = card ? excerpt(card.body, 190) : SITE_TAGLINE;
  const credit = card?.credit ?? "";

  // Candlelight dark palette (design/candlelight.md); OG images are fixed images, not themed.
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
          <div style={{ display: "flex", fontSize: 30, fontWeight: 700, letterSpacing: 1 }}>
            {SITE_NAME}
            <span style={{ color: "#e9a23b" }}>.</span>
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
            {title}
          </div>
          <div style={{ display: "flex", marginTop: 28, fontSize: 30, lineHeight: 1.4, color: "#d9cdba" }}>{text}</div>
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
          {credit ? excerpt(credit, 120) : "Big ideas from great books, one minute at a time."}
        </div>
      </div>
    ),
    OG_SIZE,
  );
}

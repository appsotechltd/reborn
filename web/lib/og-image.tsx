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
          background: "#faf8f4",
          color: "#1f1c18",
          borderTop: "16px solid #8f3b1b",
          fontFamily: "serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", fontSize: 30, fontWeight: 700, color: "#8f3b1b", letterSpacing: 1 }}>
            {SITE_NAME}.
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
          <div style={{ display: "flex", marginTop: 28, fontSize: 30, lineHeight: 1.4, color: "#5c564d" }}>{text}</div>
        </div>
        <div
          style={{
            display: "flex",
            borderTop: "2px solid #e2dcd1",
            paddingTop: 20,
            fontSize: 22,
            color: "#5c564d",
          }}
        >
          {credit ? excerpt(credit, 120) : "Big ideas from great books, one minute at a time."}
        </div>
      </div>
    ),
    OG_SIZE,
  );
}

import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CardView } from "@/components/CardView";
import { makeCard } from "./fixtures";

describe("<CardView>", () => {
  it("has no source section at the bottom; the byline links to the source page", () => {
    const card = makeCard();
    render(<CardView card={card} />);
    expect(screen.queryByTestId("card-credit")).toBeNull();
    const byline = screen.getByTestId("card-byline");
    expect(within(byline).getByRole("link", { name: "An Example Book" }).getAttribute("href")).toBe("/sources/example-book");
  });

  it("labels the note on grief and heartbreak cards as support, even when flagged health", () => {
    render(<CardView card={makeCard({ health: true, topic: "grief-loss", disclaimer: "You don't have to go through it alone." })} />);
    const note = screen.getByRole("note", { name: /support note/i });
    expect(note.textContent).toContain("Support note:");
  });

  it("shows the health disclaimer when present", () => {
    const disclaimer = "This is general information, not medical advice.";
    render(<CardView card={makeCard({ health: true, topic: "health", disclaimer })} />);
    const note = screen.getByRole("note", { name: /health disclaimer/i });
    expect(note.textContent).toContain(disclaimer);
  });

  it("shows no disclaimer when there is none", () => {
    render(<CardView card={makeCard()} />);
    expect(screen.queryByRole("note")).toBeNull();
  });

  it("keeps the disclaimer with extra children and actions", () => {
    render(
      <CardView
        card={makeCard({ health: true, disclaimer: "Not medical advice.", credit: "Source: Someone, Something, CC BY 4.0" })}
        headingLevel="h2"
        actions={<button type="button">Listen</button>}
      >
        <p>Quiz goes here</p>
      </CardView>,
    );
    expect(screen.queryByText("Source: Someone, Something, CC BY 4.0")).toBeNull();
    expect(screen.getByRole("note").textContent).toContain("Not medical advice.");
    expect(screen.getByRole("heading", { level: 2, name: "Small steps beat big plans" })).toBeTruthy();
  });

  it("renders body paragraphs, the quote and Apply it", () => {
    render(<CardView card={makeCard({ quote: "A short quote." })} />);
    expect(screen.getByText("A first paragraph about taking small steps.")).toBeTruthy();
    expect(screen.getByText("A second paragraph about keeping going.")).toBeTruthy();
    expect(screen.getByText("“A short quote.”")).toBeTruthy();
    expect(screen.getByRole("region", { name: "Apply it" }).textContent).toContain("Pick one tiny step");
  });
});

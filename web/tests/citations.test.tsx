import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CitedText } from "@/components/CitedText";
import { parseCitations } from "@/lib/citations";
import { makeCard } from "./fixtures";

const a = makeCard({ id: "example-book--01", title: "Small steps beat big plans" });
const b = makeCard({ id: "another-source--12", title: "Rest is part of the work" });

describe("parseCitations", () => {
  it("splits text and [card-id] citations, numbering by the citations order", () => {
    const segs = parseCitations("Start small [another-source--12]. Then rest [example-book--01][another-source--12].", [b, a]);
    expect(segs).toEqual([
      { type: "text", text: "Start small " },
      { type: "citation", id: "another-source--12", card: b, index: 1 },
      { type: "text", text: ". Then rest " },
      { type: "citation", id: "example-book--01", card: a, index: 2 },
      { type: "citation", id: "another-source--12", card: b, index: 1 },
      { type: "text", text: "." },
    ]);
  });

  it("ignores bracketed text that is not a card id", () => {
    const segs = parseCitations("See [note] and [Example--01] and [x--].", []);
    expect(segs).toEqual([{ type: "text", text: "See [note] and [Example--01] and [x--]." }]);
  });

  it("still links ids missing from citations, numbered after the known ones", () => {
    const segs = parseCitations("[made-up--03] and [example-book--01]", [a]);
    expect(segs[0]).toEqual({ type: "citation", id: "made-up--03", card: undefined, index: 2 });
    expect(segs[2]).toMatchObject({ type: "citation", id: "example-book--01", index: 1 });
  });
});

describe("<CitedText>", () => {
  it("renders citations as links to the idea pages", () => {
    render(
      <CitedText
        text={"Take one step [example-book--01].\n\nThen rest [another-source--12]."}
        citations={[a, b]}
      />,
    );
    const first = screen.getByRole("link", { name: "Source 1: Small steps beat big plans" });
    expect(first.getAttribute("href")).toBe("/ideas/example-book--01");
    expect(first.textContent).toBe("1");
    const second = screen.getByRole("link", { name: "Source 2: Rest is part of the work" });
    expect(second.getAttribute("href")).toBe("/ideas/another-source--12");
    // Raw ids are not shown as text.
    expect(screen.queryByText(/\[example-book--01\]/)).toBeNull();
    // Paragraphs are preserved.
    expect(document.querySelectorAll("p")).toHaveLength(2);
  });
});

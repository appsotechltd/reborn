import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { WordCounter } from "@/components/WordCounter";
import { countWords, wordCountState } from "@/lib/words";

const words = (n: number) => Array.from({ length: n }, (_, i) => `w${i}`).join(" ");

describe("countWords", () => {
  it("counts whitespace-separated words, including across paragraphs", () => {
    expect(countWords("")).toBe(0);
    expect(countWords("   \n ")).toBe(0);
    expect(countWords("one")).toBe(1);
    expect(countWords("  one two\tthree\n\nfour  ")).toBe(4);
    expect(countWords("don't over-think it")).toBe(3);
  });

  it("classifies against the 25–160 rule", () => {
    expect(wordCountState(0)).toBe("empty");
    expect(wordCountState(24)).toBe("short");
    expect(wordCountState(25)).toBe("ok");
    expect(wordCountState(160)).toBe("ok");
    expect(wordCountState(161)).toBe("long");
  });
});

describe("<WordCounter>", () => {
  it("prompts when empty", () => {
    render(<WordCounter text="" />);
    expect(screen.getByText(/aim for 25–160 words/i)).toBeTruthy();
  });

  it("shows the live count and state", () => {
    const { rerender, container } = render(<WordCounter text={words(10)} />);
    expect(screen.getByText("10 words")).toBeTruthy();
    expect(container.querySelector("[data-state]")?.getAttribute("data-state")).toBe("short");

    rerender(<WordCounter text={words(1)} />);
    expect(screen.getByText("1 word")).toBeTruthy();

    rerender(<WordCounter text={words(80)} />);
    expect(screen.getByText("80 words")).toBeTruthy();
    expect(container.querySelector("[data-state]")?.getAttribute("data-state")).toBe("ok");

    rerender(<WordCounter text={words(170)} />);
    expect(container.querySelector("[data-state]")?.getAttribute("data-state")).toBe("long");
    expect(screen.getByText(/too long/)).toBeTruthy();
  });
});

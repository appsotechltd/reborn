import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AskView } from "@/app/ask/AskView";
import { AuthProvider } from "@/lib/auth";
import { makeCard } from "./fixtures";

const user = { id: "u1", email: "a@example.org", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function mockChat(response: Response) {
  const fetchMock = vi.fn(async (url: string) => (String(url).endsWith("/v1/me") ? json(200, user) : response.clone()));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

async function ask(question: string) {
  render(
    <AuthProvider>
      <AskView />
    </AuthProvider>,
  );
  fireEvent.change(screen.getByLabelText("Your question"), { target: { value: question } });
  fireEvent.click(screen.getByRole("button", { name: "Ask" }));
}

describe("<AskView>", () => {
  beforeEach(() => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
  });
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("links inline citations to cards and sends the full history", async () => {
    const card = makeCard();
    const fetchMock = mockChat(json(200, { reply: `Start small [${card.id}].`, citations: [card] }));
    await ask("How do I start?");
    const link = await screen.findByRole("link", { name: `Source 1: ${card.title}` });
    expect(link.getAttribute("href")).toBe(`/ideas/${card.id}`);
    expect(screen.getByText(card.credit)).toBeTruthy();
    const chatCall = fetchMock.mock.calls.find(([u]) => String(u).endsWith("/v1/agent/chat"))!;
    const body = JSON.parse(((chatCall as unknown as [string, RequestInit])[1]).body as string);
    expect(body).toEqual({ messages: [{ role: "user", content: "How do I start?" }] });
  });

  it("shows a friendly state when the guide is unavailable (503)", async () => {
    mockChat(json(503, { error: { code: "agent_unavailable", message: "the guide is not configured" } }));
    await ask("Hello?");
    expect(await screen.findByText("The guide is resting")).toBeTruthy();
    expect((screen.getByLabelText("Your question") as HTMLTextAreaElement).value).toBe("Hello?");
  });

  it("explains the hourly limit (429)", async () => {
    mockChat(json(429, { error: { code: "rate_limited", message: "slow down" } }));
    await ask("Again?");
    expect(await screen.findByText("Time for a pause")).toBeTruthy();
  });
});

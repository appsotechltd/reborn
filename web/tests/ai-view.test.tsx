import { fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AIView } from "@/app/ai/AIView";
import { packRate, recordingFormat, walletSummary } from "@/lib/ai";
import { AuthProvider } from "@/lib/auth";
import type { AIStatus, AIWallet } from "@/lib/types";
import { makeCard } from "./fixtures";

const user = { id: "u1", email: "a@example.org", display_name: "Ada", role: "member", topics: [], premium: true };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const wallet = (over: Partial<AIWallet> = {}): AIWallet => ({
  monthly_units: 250,
  allowance_used: 10,
  allowance_left: 240,
  topup_units: 0,
  remaining: 240,
  resets_at: "2026-11-01T00:00:00Z",
  ...over,
});

const status = (over: Partial<AIStatus> = {}): AIStatus => ({
  available: true,
  premium: true,
  wallet: wallet(),
  rates: [
    { kind: "text", units: 1, per: "reply" },
    { kind: "picture", units: 12, per: "picture" },
  ],
  packs: [{ id: "units_250", name: "250 AI units", units: 250, amount_cents: 299, currency: "usd", product_id: "reborn.ai.units250" }],
  providers: { stripe: true, apple: false, google: false },
  ...over,
});

function mockApi(routes: Record<string, Response>) {
  const fetchMock = vi.fn(async (url: string) => {
    const path = new URL(String(url)).pathname;
    if (path === "/v1/me") return json(200, user);
    const res = routes[path];
    return res ? res.clone() : json(404, { error: { code: "not_found", message: "nope" } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function show() {
  render(
    <AuthProvider>
      <AIView />
    </AuthProvider>,
  );
}

describe("<AIView>", () => {
  beforeEach(() => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
  });
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("offers Premium, with the unit rates, to members without it", async () => {
    mockApi({ "/v1/ai": json(200, status({ premium: false, wallet: wallet({ monthly_units: 0, allowance_left: 0, remaining: 0 }) })) });
    show();
    expect(await screen.findByText("Reborn AI comes with Premium")).toBeTruthy();
    const rates = screen.getByRole("list", { name: "AI unit rates" });
    expect(within(rates).getByText("A photo-like picture")).toBeTruthy();
    expect(within(rates).getByText("12 units")).toBeTruthy();
    expect(screen.getByRole("link", { name: "See Premium" }).getAttribute("href")).toBe("/premium");
  });

  it("sends a message and shows the reply, its chart, cited cards and the new balance", async () => {
    const card = makeCard();
    const conversation = { id: "c1", title: "Plan", created_at: "", updated_at: "" };
    const fetchMock = mockApi({
      "/v1/ai": json(200, status()),
      "/v1/ai/conversations": json(200, { conversations: [] }),
      "/v1/ai/chat": json(200, {
        conversation,
        user_message: { id: "m1", role: "user", content: "Plan my week", voice: false, citations: [], attachments: [], units: 0, created_at: "" },
        message: {
          id: "m2",
          role: "assistant",
          content: `Start small [${card.id}].`,
          voice: false,
          citations: [card],
          attachments: [
            { type: "chart", alt: "Week", chart: { kind: "bar", title: "Minutes a day", labels: ["Mon", "Tue"], series: [{ name: "Minutes", values: [5, 10] }] } },
          ],
          units: 2,
          created_at: "",
        },
        wallet: wallet({ allowance_left: 238, remaining: 238 }),
      }),
    });
    show();
    expect(await screen.findByText("240 units")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Message Reborn AI"), { target: { value: "Plan my week" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));

    expect(await screen.findByRole("link", { name: `Source 1: ${card.title}` })).toBeTruthy();
    expect(screen.getByText("Minutes a day")).toBeTruthy();
    expect(screen.getByRole("img", { name: /Minutes a day: Mon 5, Tue 10/ })).toBeTruthy();
    expect(screen.getByText("Used 2 units")).toBeTruthy();
    expect(screen.getByText("238 units")).toBeTruthy();
    const call = fetchMock.mock.calls.find(([u]) => String(u).endsWith("/v1/ai/chat"))!;
    expect(JSON.parse((call as unknown as [string, RequestInit])[1].body as string)).toEqual({ message: "Plan my week" });
  });

  it("explains running out of units and opens the top-ups", async () => {
    mockApi({
      "/v1/ai": json(200, status({ wallet: wallet({ allowance_left: 0, remaining: 0 }) })),
      "/v1/ai/conversations": json(200, { conversations: [] }),
      "/v1/ai/chat": json(402, { error: { code: "out_of_units", message: "out" }, wallet: wallet({ allowance_left: 0, remaining: 0 }) }),
    });
    show();
    fireEvent.change(await screen.findByLabelText("Message Reborn AI"), { target: { value: "Hi" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(await screen.findByText("You're out of AI units")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Top up AI units" })).toBeTruthy();
    expect(screen.getByText("$2.99")).toBeTruthy();
    expect((screen.getByLabelText("Message Reborn AI") as HTMLTextAreaElement).value).toBe("Hi");
  });
});

describe("Reborn AI helpers", () => {
  it("summarises the wallet", () => {
    expect(walletSummary(wallet())).toBe("240 of 250 units left this month");
    expect(walletSummary(wallet({ topup_units: 600 }))).toBe("240 of 250 units left this month, plus 600 units from top-ups");
    expect(walletSummary(wallet({ monthly_units: 0, allowance_left: 0, topup_units: 0 }))).toBe("No AI units left");
  });

  it("compares packs per 100 units", () => {
    expect(packRate({ id: "p", name: "", units: 1300, amount_cents: 1199, currency: "usd", product_id: "" })).toBe("$0.92 per 100");
  });

  it("picks a recording format the server accepts", () => {
    expect(recordingFormat((t) => t === "audio/mp4")).toEqual({ mimeType: "audio/mp4", ext: "m4a" });
    expect(recordingFormat(() => false)).toBeNull();
  });
});

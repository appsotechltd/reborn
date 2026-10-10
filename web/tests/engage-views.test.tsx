import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Inbox } from "@/app/notifications/NotificationsView";
import { PremiumView } from "@/app/premium/PremiumView";
import { Composer } from "@/app/circles/[id]/CircleThread";
import { JoinView } from "@/app/join/JoinView";
import { AuthForm } from "@/components/AuthForm";
import { AuthProvider } from "@/lib/auth";
import { makeCard } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  usePathname: () => "/",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
type Call = [string, RequestInit | undefined];

function stubApi(routes: (url: string, init?: RequestInit) => Response | undefined) {
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    const u = String(url);
    return routes(u, init) ?? (u.endsWith("/v1/me") ? json(200, user) : new Response(null, { status: 204 }));
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}
const calls = (f: ReturnType<typeof stubApi>) => f.mock.calls as unknown as Call[];
const signIn = () => window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));

afterEach(() => {
  window.localStorage.clear();
  vi.unstubAllGlobals();
});

describe("notifications inbox", () => {
  beforeEach(signIn);

  it("marks everything read and updates the unread state", async () => {
    const notifications = [
      { id: "n1", kind: "reply", text: "Bob replied to your comment", actor: null, post_id: "p--01", comment_id: "c1", circle_id: null, read_at: null, created_at: "2026-10-10T09:00:00Z" },
      { id: "n2", kind: "follow", text: "Cy started following you", actor: { id: "c", handle: "cy", display_name: "Cy" }, post_id: null, comment_id: null, circle_id: null, read_at: null, created_at: "2026-10-10T08:00:00Z" },
    ];
    const f = stubApi((u) => (u.includes("/v1/notifications?") ? json(200, { notifications, unread: 2 }) : undefined));
    render(
      <AuthProvider>
        <Inbox />
      </AuthProvider>,
    );
    expect(await screen.findByText("2 unread")).toBeTruthy();
    expect(screen.getByRole("link", { name: /Bob replied/ }).getAttribute("href")).toBe("/ideas/p--01#comment-c1");
    expect(screen.getByRole("link", { name: /Cy started/ }).getAttribute("href")).toBe("/u/cy");
    fireEvent.click(screen.getByRole("button", { name: "Mark all as read" }));
    expect(await screen.findByText("All caught up")).toBeTruthy();
    const read = calls(f).find(([u]) => u.endsWith("/v1/notifications/read"));
    expect(read?.[1]?.method).toBe("POST");
    expect(read?.[1]?.body).toBeUndefined();
  });

  it("marks one notification read when it is opened", async () => {
    const notifications = [
      { id: "n1", kind: "circle", text: "Ann in Stoics: hello", actor: null, post_id: null, comment_id: null, circle_id: "k1", read_at: null, created_at: "2026-10-10T09:00:00Z" },
    ];
    const f = stubApi((u) => (u.includes("/v1/notifications?") ? json(200, { notifications, unread: 1 }) : undefined));
    render(
      <AuthProvider>
        <Inbox />
      </AuthProvider>,
    );
    const link = await screen.findByRole("link", { name: /Ann in Stoics/ });
    link.addEventListener("click", (e) => e.preventDefault());
    fireEvent.click(link);
    await waitFor(() => expect(calls(f).some(([u, i]) => u.endsWith("/v1/notifications/read") && i?.body === JSON.stringify({ ids: ["n1"] }))).toBe(true));
    expect(await screen.findByText("All caught up")).toBeTruthy();
  });
});

describe("referral code carried into sign-up", () => {
  it("stores the code from /join and sends it, with the timezone, when registering", async () => {
    const f = stubApi((u) => (u.endsWith("/v1/auth/register") ? json(201, { token: "t", user }) : undefined));
    const { unmount } = render(
      <AuthProvider>
        <JoinView code="7F3A9C21" />
      </AuthProvider>,
    );
    expect(screen.getByRole("link", { name: "Create your free account" }).getAttribute("href")).toBe("/register?ref=7F3A9C21");
    unmount();

    render(
      <AuthProvider>
        <AuthForm mode="register" next="/" />
      </AuthProvider>,
    );
    expect((screen.getByLabelText(/Invite code/) as HTMLInputElement).value).toBe("7F3A9C21");
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Bea" } });
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "bea@example.org" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "password1" } });
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));
    await waitFor(() => expect(calls(f).some(([u]) => u.endsWith("/v1/auth/register"))).toBe(true));
    const [, init] = calls(f).find(([u]) => u.endsWith("/v1/auth/register"))!;
    const body = JSON.parse(String(init?.body));
    expect(body.referral_code).toBe("7F3A9C21");
    expect(typeof body.timezone).toBe("string");
    await waitFor(() => expect(window.localStorage.getItem("reborn.referral")).toBeNull());
  });

  it("prefers a code in the register link", () => {
    stubApi(() => undefined);
    render(
      <AuthProvider>
        <AuthForm mode="register" next="/" referral="LINKCODE1" />
      </AuthProvider>,
    );
    expect((screen.getByLabelText(/Invite code/) as HTMLInputElement).value).toBe("LINKCODE1");
  });
});

describe("circle message posting", () => {
  beforeEach(signIn);

  it("posts the message with an attached idea and hands it back", async () => {
    const card = makeCard({ id: "example-book--02", title: "A second idea" });
    const message = { id: "m1", circle_id: "k1", body: "Loved this", post_id: card.id, author: user, created_at: "2026-10-10T10:00:00Z" };
    const f = stubApi((u, i) => (u.endsWith("/v1/circles/k1/messages") && i?.method === "POST" ? json(201, message) : undefined));
    const onPosted = vi.fn();
    render(
      <AuthProvider>
        <Composer circleId="k1" cards={[makeCard(), card]} onPosted={onPosted} />
      </AuthProvider>,
    );
    fireEvent.change(screen.getByLabelText("Your message"), { target: { value: "  Loved this  " } });
    fireEvent.change(screen.getByLabelText("Attach an idea from this book"), { target: { value: card.id } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await waitFor(() => expect(onPosted).toHaveBeenCalledWith(message));
    const [, init] = calls(f).find(([u, i]) => u.endsWith("/v1/circles/k1/messages") && i?.method === "POST")!;
    expect(JSON.parse(String(init?.body))).toEqual({ body: "Loved this", post_id: card.id });
    expect((screen.getByLabelText("Your message") as HTMLTextAreaElement).value).toBe("");
  });

  it("shows the server's error and keeps the draft", async () => {
    stubApi((u, i) =>
      u.endsWith("/messages") && i?.method === "POST" ? json(403, { error: { code: "forbidden", message: "join the circle first" } }) : undefined,
    );
    render(
      <AuthProvider>
        <Composer circleId="k1" cards={[]} onPosted={vi.fn()} />
      </AuthProvider>,
    );
    fireEvent.change(screen.getByLabelText("Your message"), { target: { value: "Hi" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(await screen.findByText("join the circle first")).toBeTruthy();
    expect((screen.getByLabelText("Your message") as HTMLTextAreaElement).value).toBe("Hi");
  });
});

describe("premium status", () => {
  const plans = [
    { id: "monthly", name: "Premium monthly", amount_cents: 499, currency: "usd", interval: "month", product_id: "reborn.premium.monthly" },
    { id: "yearly", name: "Premium yearly", amount_cents: 3999, currency: "usd", interval: "year", product_id: "reborn.premium.yearly" },
  ];

  it("shows an active web subscription with Manage billing", async () => {
    signIn();
    stubApi((u) =>
      u.endsWith("/v1/premium")
        ? json(200, {
            plans,
            providers: { stripe: true, apple: false, google: false },
            premium: true,
            premium_until: "2026-11-10T00:00:00Z",
            subscription: { provider: "stripe", plan: "monthly", status: "active", expires_at: "2026-11-10T00:00:00Z" },
          })
        : undefined,
    );
    render(
      <AuthProvider>
        <PremiumView />
      </AuthProvider>,
    );
    const status = await screen.findByTestId("premium-status");
    expect(status.textContent).toMatch(/Premium member \(monthly, renews/);
    expect(screen.getByRole("button", { name: "Manage billing" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Subscribe" })).toBeNull();
  });

  it("shows the plans as coming soon when Stripe is off", async () => {
    signIn();
    stubApi((u) =>
      u.endsWith("/v1/premium")
        ? json(200, { plans, providers: { stripe: false, apple: false, google: false }, premium: false, premium_until: null, subscription: null })
        : undefined,
    );
    render(
      <AuthProvider>
        <PremiumView welcome />
      </AuthProvider>,
    );
    expect(await screen.findByText("Premium on the web is coming soon.")).toBeTruthy();
    expect(screen.getByText("$4.99 / month")).toBeTruthy();
    expect(screen.getByText("$39.99 / year")).toBeTruthy();
    for (const b of screen.getAllByRole("button", { name: "Subscribe" })) expect((b as HTMLButtonElement).disabled).toBe(true);
    expect(screen.getByText(/Welcome to Premium/)).toBeTruthy();
    expect(screen.getByTestId("premium-status").textContent).toMatch(/free plan/);
  });
});

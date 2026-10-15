import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ShareMenu } from "@/components/ShareMenu";
import { AuthProvider } from "@/lib/auth";
import { SiteUrlProvider } from "@/lib/site-url";

function renderMenu(props: Parameters<typeof ShareMenu>[0]) {
  render(
    <SiteUrlProvider url="https://iamreborn.app">
      <AuthProvider>
        <ShareMenu {...props} />
      </AuthProvider>
    </SiteUrlProvider>,
  );
  fireEvent.click(screen.getByRole("button", { name: /share/i }));
}

describe("<ShareMenu> for pages that aren't ideas", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("shares the page link to every network and never counts it as an idea share", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    renderMenu({ path: "/sources/meditations", title: "Meditations by Marcus Aurelius", what: "book", label: true });

    expect(screen.getByRole("heading", { name: "Share this book" })).toBeTruthy();
    const url = "https://iamreborn.app/sources/meditations";
    expect((screen.getByLabelText("Link to this book") as HTMLInputElement).value).toBe(url);
    const whatsapp = screen.getByRole("link", { name: /WhatsApp/ });
    expect(whatsapp.getAttribute("href")).toContain(encodeURIComponent(url));
    for (const name of [/Facebook/, /^X/, /LinkedIn/, /Telegram/, /Email/]) {
      expect(screen.getByRole("link", { name })).toBeTruthy();
    }
    fireEvent.click(whatsapp);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

import { describe, expect, it, vi } from "vitest";
import { ApiError, apiRequest, buildUrl, createApiClient, errorFromResponse, isApiError } from "@/lib/api";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

describe("errorFromResponse", () => {
  it("reads the API error shape", async () => {
    const err = await errorFromResponse(json(404, { error: { code: "not_found", message: "card not found" } }));
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(404);
    expect(err.code).toBe("not_found");
    expect(err.message).toBe("card not found");
  });

  it("falls back to a generic message when the body is not JSON", async () => {
    const err = await errorFromResponse(new Response("<html>Bad gateway</html>", { status: 502 }));
    expect(err.status).toBe(502);
    expect(err.code).toBe("http_502");
    expect(err.message).toMatch(/502/);
  });

  it("falls back when the JSON has no error object", async () => {
    const err = await errorFromResponse(json(429, { nope: true }));
    expect(err.code).toBe("http_429");
    expect(err.message).toMatch(/too many requests/i);
  });
});

describe("apiRequest", () => {
  it("sends JSON and the bearer token, and parses the response", async () => {
    const fetchImpl = vi.fn(async () => json(200, { ok: 1 }));
    const res = await apiRequest<{ ok: number }>("http://api.test/", "/v1/stashes", {
      method: "POST",
      body: { name: "Morning" },
      token: "tok",
      fetchImpl,
    });
    expect(res).toEqual({ ok: 1 });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("http://api.test/v1/stashes");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ name: "Morning" }));
    expect((init.headers as Record<string, string>).Authorization).toBe("Bearer tok");
    expect((init.headers as Record<string, string>)["Content-Type"]).toBe("application/json");
  });

  it("resolves undefined for 204 No Content", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    await expect(apiRequest("http://api.test", "/v1/stashes/x", { method: "DELETE", fetchImpl })).resolves.toBeUndefined();
  });

  it("throws ApiError with the server's code and message", async () => {
    const fetchImpl = vi.fn(async () =>
      json(503, { error: { code: "agent_unavailable", message: "the guide is not configured" } }),
    );
    const err = await apiRequest("http://api.test", "/v1/agent/chat", { method: "POST", body: {}, fetchImpl }).catch(
      (e) => e,
    );
    expect(isApiError(err)).toBe(true);
    expect(err).toMatchObject({ status: 503, code: "agent_unavailable", message: "the guide is not configured" });
  });

  it("maps network failures to status 0 / network_error", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("fetch failed");
    });
    const err = await apiRequest("http://api.test", "/v1/topics", { fetchImpl }).catch((e) => e);
    expect(err).toMatchObject({ status: 0, code: "network_error" });
  });
});

describe("buildUrl and client", () => {
  it("drops empty query values", () => {
    expect(buildUrl("http://a", "/v1/feed", { topics: "health", cursor: null, limit: 20, q: "" })).toBe(
      "http://a/v1/feed?topics=health&limit=20",
    );
  });

  it("uses the token getter and encodes path segments", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const api = createApiClient("http://a", () => "abc", fetchImpl);
    await api.addToStash("stash 1", "example-book--01");
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("http://a/v1/stashes/stash%201/cards/example-book--01");
    expect(init.method).toBe("PUT");
    expect((init.headers as Record<string, string>).Authorization).toBe("Bearer abc");
  });

  it("does not send the token to login", async () => {
    const fetchImpl = vi.fn(async () => json(200, { token: "t", user: {} }));
    const api = createApiClient("http://a", () => "old", fetchImpl);
    await api.login({ email: "a@b.c", password: "password1" });
    const [, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
  });
});

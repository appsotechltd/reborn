import { describe, expect, it } from "vitest";
import { markNotificationsRead, mergeMessages, notificationHref, premiumSummary } from "@/lib/engage";
import type { AppNotification } from "@/lib/types";

const note = (id: string, over: Partial<AppNotification> = {}): AppNotification => ({
  id,
  kind: "reply",
  text: "Bob replied to your comment",
  actor: { id: "b", handle: "bob", display_name: "Bob" },
  post_id: null,
  comment_id: null,
  circle_id: null,
  read_at: null,
  created_at: "2026-10-10T09:00:00Z",
  ...over,
});

describe("notification read state", () => {
  it("marks chosen notifications read and recounts unread", () => {
    const list = [note("a"), note("b"), note("c", { read_at: "2026-10-09T00:00:00Z" })];
    const r = markNotificationsRead(list, ["a"], "2026-10-10T10:00:00Z");
    expect(r.unread).toBe(1);
    expect(r.notifications[0].read_at).toBe("2026-10-10T10:00:00Z");
    expect(r.notifications[1].read_at).toBeNull();
    // Already-read items keep their original time.
    expect(r.notifications[2].read_at).toBe("2026-10-09T00:00:00Z");
  });

  it("marks everything read when no ids are given", () => {
    const r = markNotificationsRead([note("a"), note("b")]);
    expect(r.unread).toBe(0);
    expect(r.notifications.every((n) => n.read_at)).toBe(true);
  });

  it("links each kind to its comment, post, circle or profile", () => {
    expect(notificationHref(note("a", { post_id: "p--01", comment_id: "c1" }))).toBe("/ideas/p--01#comment-c1");
    expect(notificationHref(note("a", { kind: "daily", actor: null, post_id: "p--02" }))).toBe("/ideas/p--02");
    expect(notificationHref(note("a", { kind: "circle", circle_id: "k1" }))).toBe("/circles/k1");
    expect(notificationHref(note("a", { kind: "follow" }))).toBe("/u/bob");
    expect(notificationHref(note("a", { kind: "reward", actor: null }))).toBe("/premium");
  });
});

describe("mergeMessages", () => {
  const m = (id: string, t: string) => ({ id, created_at: t });
  it("dedupes and orders oldest first", () => {
    const out = mergeMessages([m("b", "2026-10-10T10:00:01Z"), m("a", "2026-10-10T10:00:00Z")], [m("c", "2026-10-10T10:00:02.5Z"), m("b", "2026-10-10T10:00:01Z")]);
    expect(out.map((x) => x.id)).toEqual(["a", "b", "c"]);
  });
  it("drops messages the latest page no longer has", () => {
    const shown = [m("old", "2026-10-10T09:00:00Z"), m("gone", "2026-10-10T10:00:01Z"), m("b", "2026-10-10T10:00:02Z")];
    expect(mergeMessages(shown, [m("b", "2026-10-10T10:00:02Z")], "2026-10-10T10:00:00Z").map((x) => x.id)).toEqual(["old", "b"]);
    expect(mergeMessages(shown, [m("b", "2026-10-10T10:00:02Z")], "").map((x) => x.id)).toEqual(["b"]);
  });
});

describe("premiumSummary", () => {
  it("describes free, renewing, cancelled and gifted premium", () => {
    expect(premiumSummary({ premium: false, premium_until: null, subscription: null })).toMatch(/free plan/);
    expect(
      premiumSummary({
        premium: true,
        premium_until: "2026-11-10T00:00:00Z",
        subscription: { provider: "stripe", plan: "monthly", status: "active", expires_at: "2026-11-10T00:00:00Z" },
      }),
    ).toMatch(/Premium member \(monthly, renews/);
    expect(
      premiumSummary({
        premium: true,
        premium_until: "2026-11-10T00:00:00Z",
        subscription: { provider: "stripe", plan: "yearly", status: "canceled", expires_at: "2026-11-10T00:00:00Z" },
      }),
    ).toMatch(/won't renew/);
    expect(premiumSummary({ premium: true, premium_until: "2026-10-24T00:00:00Z", subscription: null })).toMatch(/You have Premium until/);
  });
});

import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SubjectCard, SubjectGuides, SubjectList, SubjectStepLink } from "@/components/Subjects";
import { SummaryReader } from "@/components/SummaryReader";
import { AuthProvider } from "@/lib/auth";
import { guideState, subjectHref, subjectMeta, subjectPlan, subjectProgressLabel } from "@/lib/subjects";
import { saveLocalProgress } from "@/lib/summaries";
import type { Subject, SubjectDetail, Summary, SummaryDetail, SummaryProgress } from "@/lib/types";
import { makeCard } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function makeGuide(n: number, viewer?: SummaryProgress): Summary {
  return {
    id: `clarity-${n}`,
    kind: "topic",
    title: `Guide number ${n}`,
    description: `Guide ${n}.`,
    topic: "life-guides",
    topic_name: "Life Guides",
    coverage: "guide",
    authors: [],
    source_count: 3,
    part_count: 30,
    minutes: 9,
    published_at: "2026-10-14T00:00:00Z",
    viewer,
  };
}

function makeSubject(overrides: Partial<Subject> = {}): Subject {
  return {
    id: "communication-clarity",
    title: "Communication Clarity",
    description: "Say what you mean, so people hear it.",
    topics: ["life-guides", "communication"],
    guide_count: 3,
    part_count: 90,
    minutes: 27,
    ...overrides,
  };
}

function makeSubjectDetail(viewers: (SummaryProgress | undefined)[] = []): SubjectDetail {
  return { ...makeSubject(), guides: [1, 2, 3].map((n) => makeGuide(n, viewers[n - 1])) };
}

const done: SummaryProgress = { started: true, position: 29, finished: true };
const reading: SummaryProgress = { started: true, position: 3, finished: false };

afterEach(() => {
  window.localStorage.clear();
  vi.unstubAllGlobals();
});

describe("subject helpers", () => {
  it("describes subjects and their progress", () => {
    expect(subjectHref("communication-clarity")).toBe("/subjects/communication-clarity");
    expect(subjectMeta({ guide_count: 7, minutes: 60 })).toBe("7 guides · 60 min");
    expect(subjectMeta({ guide_count: 1, minutes: 9 })).toBe("1 guide · 9 min");
    expect(subjectProgressLabel(undefined, 7)).toBeNull();
    expect(subjectProgressLabel({ started: false, finished: 0, done: false }, 7)).toBeNull();
    expect(subjectProgressLabel({ started: true, finished: 3, done: false }, 7)).toBe("3 of 7 done");
    expect(guideState(done)).toBe("done");
    expect(guideState(reading)).toBe("in-progress");
    expect(guideState(null)).toBe("not-started");
  });

  it("starts, continues with the next unfinished guide, and reads again", () => {
    const guides = makeSubjectDetail().guides;
    const plan = (ps: (SummaryProgress | null)[]) => subjectPlan(guides, (g) => ps[guides.indexOf(g)]);
    expect(plan([null, null, null])).toMatchObject({ action: "start", href: "/summaries/clarity-1", finished: 0 });
    expect(plan([done, null, null])).toMatchObject({ action: "continue", href: "/summaries/clarity-2", finished: 1 });
    expect(plan([done, reading, null])).toMatchObject({ action: "continue", href: "/summaries/clarity-2?part=4" });
    expect(plan([done, done, done])).toMatchObject({ action: "again", href: "/summaries/clarity-1", finished: 3 });
    expect(subjectPlan([], () => null)).toBeNull();
  });
});

describe("<SubjectCard> and <SubjectList>", () => {
  it("shows the cover, guides and minutes, and links to the subject", () => {
    render(<SubjectCard subject={makeSubject({ guide_count: 7, minutes: 60 })} />);
    expect(screen.getByRole("link", { name: "Communication Clarity" }).getAttribute("href")).toBe(
      "/subjects/communication-clarity",
    );
    expect(screen.getByText("7 guides · 60 min")).toBeTruthy();
    expect(screen.queryByText(/done$/)).toBeNull();
  });

  it("shows a signed-in reader how many guides they've done", async () => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) => {
        const url = String(input);
        urls.push(url);
        if (url.endsWith("/v1/me")) return json(200, user);
        if (url.includes("/v1/subjects?topic=life-guides"))
          return json(200, {
            subjects: [makeSubject({ guide_count: 7, viewer: { started: true, finished: 3, done: false, next_summary_id: "clarity-4" } })],
          });
        return json(204, {});
      }),
    );
    render(
      <AuthProvider>
        <SubjectList subjects={[makeSubject({ guide_count: 7 })]} topic="life-guides" />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "Subjects" })).toBeTruthy();
    expect(await screen.findByText("3 of 7 done")).toBeTruthy();
  });
});

describe("<SubjectGuides>", () => {
  it("lists the guides in order and starts at the first", () => {
    render(
      <AuthProvider>
        <SubjectGuides subject={makeSubjectDetail()} />
      </AuthProvider>,
    );
    const items = within(screen.getByRole("list")).getAllByRole("listitem");
    expect(items.map((li) => li.getAttribute("data-guide-state"))).toEqual(["not-started", "not-started", "not-started"]);
    expect(items[0].textContent).toContain("Guide number 1");
    expect(within(items[1]).getByRole("link").getAttribute("href")).toBe("/summaries/clarity-2");
    expect(screen.getByRole("link", { name: "Start" }).getAttribute("href")).toBe("/summaries/clarity-1");
  });

  it("marks done and in-progress guides and continues with the next one", () => {
    render(
      <AuthProvider>
        <SubjectGuides subject={makeSubjectDetail([done, reading])} />
      </AuthProvider>,
    );
    const items = within(screen.getByRole("list")).getAllByRole("listitem");
    expect(items.map((li) => li.getAttribute("data-guide-state"))).toEqual(["done", "in-progress", "not-started"]);
    expect(items[0].textContent).toContain("Done");
    expect(items[1].textContent).toContain("In progress, part 4 of 30");
    expect(within(items[1]).getByRole("link").getAttribute("href")).toBe("/summaries/clarity-2?part=4");
    expect(screen.getByRole("link", { name: "Continue: Guide number 2" }).getAttribute("href")).toBe(
      "/summaries/clarity-2?part=4",
    );
    expect(screen.getByText("1 of 3 done")).toBeTruthy();
  });

  it("uses a signed-out reader's place in this browser", () => {
    saveLocalProgress("clarity-1", 29, true);
    saveLocalProgress("clarity-2", 29, true);
    saveLocalProgress("clarity-3", 29, true);
    render(
      <AuthProvider>
        <SubjectGuides subject={makeSubjectDetail()} />
      </AuthProvider>,
    );
    expect(screen.getByRole("link", { name: "Read again" }).getAttribute("href")).toBe("/summaries/clarity-1");
    expect(screen.getByText("3 of 3 done")).toBeTruthy();
  });

  it("loads a signed-in reader's progress from the API", async () => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) => {
        const url = String(input);
        if (url.endsWith("/v1/me")) return json(200, user);
        if (url.endsWith("/v1/subjects/communication-clarity")) return json(200, makeSubjectDetail([done, done]));
        return json(204, {});
      }),
    );
    render(
      <AuthProvider>
        <SubjectGuides subject={makeSubjectDetail()} />
      </AuthProvider>,
    );
    expect(await screen.findByRole("link", { name: "Continue: Guide number 3" })).toBeTruthy();
    expect(screen.getByText("2 of 3 done")).toBeTruthy();
  });
});

describe("<SubjectStepLink>", () => {
  it("places a guide in its subject", () => {
    render(<SubjectStepLink step={{ id: "communication-clarity", title: "Communication Clarity", step: 2, count: 7 }} />);
    const link = screen.getByRole("link");
    expect(link.textContent).toBe("Guide 2 of 7 · Communication Clarity");
    expect(link.getAttribute("href")).toBe("/subjects/communication-clarity");
  });
});

describe("<SummaryReader> in a subject", () => {
  function guideDetail(subject: SummaryDetail["subject"]): SummaryDetail {
    const parts = [1, 2].map((n) => makeCard({ id: `clarity-2--0${n}`, title: `Idea ${n}` }));
    return { ...makeGuide(2), part_count: 2, parts, subject };
  }

  async function finish() {
    fireEvent.click(screen.getByRole("button", { name: /Next/ }));
    fireEvent.click(screen.getByRole("button", { name: /Finish/ }));
    await waitFor(() => expect(screen.getByText("You've finished Guide number 2")).toBeTruthy());
  }

  it("offers the next guide at the end", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(204, {})));
    render(
      <AuthProvider>
        <SummaryReader
          summary={guideDetail({
            id: "communication-clarity",
            title: "Communication Clarity",
            step: 2,
            count: 7,
            next: { id: "clarity-3", title: "Guide number 3" },
          })}
        />
      </AuthProvider>,
    );
    await finish();
    expect(screen.getByText(/Guide 2 of 7 in/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Next guide: Guide number 3" }).getAttribute("href")).toBe(
      "/summaries/clarity-3",
    );
    expect(screen.getByRole("link", { name: "Communication Clarity" }).getAttribute("href")).toBe(
      "/subjects/communication-clarity",
    );
  });

  it("leads back to the subject after the last guide", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(204, {})));
    render(
      <AuthProvider>
        <SummaryReader summary={guideDetail({ id: "communication-clarity", title: "Communication Clarity", step: 7, count: 7 })} />
      </AuthProvider>,
    );
    await finish();
    expect(screen.queryByRole("link", { name: /Next guide/ })).toBeNull();
    expect(screen.getByRole("link", { name: "Back to Communication Clarity" }).getAttribute("href")).toBe(
      "/subjects/communication-clarity",
    );
  });
});

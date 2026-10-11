// Runway's developer API (task + polling). Check the current model names and
// allowed durations in Runway's docs before the first paid run.
const BASE = "https://api.dev.runwayml.com/v1";

export function runway({ apiKey = process.env.RUNWAYML_API_SECRET, model = process.env.RUNWAY_MODEL || "gen4.5" } = {}) {
  if (!apiKey) return null;
  const headers = { authorization: `Bearer ${apiKey}`, "x-runway-version": "2024-11-06", "content-type": "application/json" };
  return {
    name: "runway",
    model,
    clipSeconds: [5, 10],
    async start({ prompt, seconds, aspectRatio = "9:16" }) {
      const res = await fetch(`${BASE}/text_to_video`, {
        method: "POST",
        headers,
        body: JSON.stringify({ model, promptText: prompt.slice(0, 1000), ratio: aspectRatio === "9:16" ? "720:1280" : "1280:720", duration: seconds <= 5 ? 5 : 10 }),
      });
      if (!res.ok) throw new Error(`Runway ${res.status}: ${(await res.text()).slice(0, 400)}`);
      return (await res.json()).id;
    },
    async poll(id) {
      const res = await fetch(`${BASE}/tasks/${id}`, { headers });
      if (!res.ok) throw new Error(`Runway poll ${res.status}: ${(await res.text()).slice(0, 400)}`);
      const task = await res.json();
      if (task.status === "SUCCEEDED") return { done: true, url: task.output[0] };
      if (task.status === "FAILED" || task.status === "CANCELLED") throw new Error(`Runway ${task.status}: ${task.failure ?? ""}`);
      return { done: false };
    },
  };
}

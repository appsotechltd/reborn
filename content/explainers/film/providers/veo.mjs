// Google Veo through the Gemini API (long-running predict + operation polling).
// Check the current model name in Google's docs before the first paid run.
const BASE = "https://generativelanguage.googleapis.com/v1beta";

export function veo({ apiKey = process.env.GEMINI_API_KEY, model = process.env.VEO_MODEL || "veo-3.0-generate-001" } = {}) {
  if (!apiKey) return null;
  const headers = { "x-goog-api-key": apiKey, "content-type": "application/json" };
  return {
    name: "veo",
    model,
    clipSeconds: [4, 8],
    async start({ prompt, negativePrompt, seconds, aspectRatio = "9:16" }) {
      const res = await fetch(`${BASE}/models/${model}:predictLongRunning`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          instances: [{ prompt }],
          parameters: { aspectRatio, negativePrompt, durationSeconds: seconds, personGeneration: "allow_adult" },
        }),
      });
      if (!res.ok) throw new Error(`Veo ${res.status}: ${(await res.text()).slice(0, 400)}`);
      return (await res.json()).name;
    },
    async poll(operation) {
      const res = await fetch(`${BASE}/${operation}`, { headers });
      if (!res.ok) throw new Error(`Veo poll ${res.status}: ${(await res.text()).slice(0, 400)}`);
      const op = await res.json();
      if (!op.done) return { done: false };
      if (op.error) throw new Error(`Veo failed: ${op.error.message}`);
      const uri = op.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri;
      if (!uri) throw new Error(`Veo returned no video (it may have been filtered): ${JSON.stringify(op.response).slice(0, 300)}`);
      return { done: true, url: uri, headers: { "x-goog-api-key": apiKey } };
    },
  };
}

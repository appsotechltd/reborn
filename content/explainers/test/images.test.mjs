import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { openai, ideogram, imagen, pickProvider, makeImage, fullPrompt, STYLE } from "../src/images.mjs";

const PNG = Buffer.from("fake-png");
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function recorder(respond) {
  const calls = [];
  const fetch = async (url, init = {}) => { calls.push({ url: String(url), init }); return respond(String(url), init); };
  return { calls, fetch };
}

test("openai sends a portrait request and decodes the image", async () => {
  const r = recorder(() => json({ data: [{ b64_json: PNG.toString("base64") }] }));
  const p = openai({ apiKey: "k", fetch: r.fetch });
  assert.deepEqual(await p.generate("a candle"), PNG);
  assert.equal(r.calls[0].url, "https://api.openai.com/v1/images/generations");
  assert.equal(r.calls[0].init.headers.authorization, "Bearer k");
  const body = JSON.parse(r.calls[0].init.body);
  assert.equal(body.model, "gpt-image-1");
  assert.equal(body.size, "1024x1536");
  assert.equal(body.prompt, "a candle");
});

test("ideogram posts a 9x16 form and downloads the returned image", async () => {
  const r = recorder((url) => url.includes("/generate") ? json({ data: [{ url: "https://ideogram.example/img.png" }] }) : new Response(PNG));
  const p = ideogram({ apiKey: "k", fetch: r.fetch });
  assert.deepEqual(await p.generate('a wall with "Life is long"'), PNG);
  assert.equal(r.calls[0].url, "https://api.ideogram.ai/v1/ideogram-v3/generate");
  assert.equal(r.calls[0].init.headers["Api-Key"], "k");
  assert.equal(r.calls[0].init.body.get("aspect_ratio"), "9x16");
  assert.equal(r.calls[0].init.body.get("magic_prompt"), "OFF");
  assert.equal(r.calls[1].url, "https://ideogram.example/img.png");
});

test("provider errors carry the status and message", async () => {
  const r = recorder(() => new Response("quota exceeded", { status: 429 }));
  await assert.rejects(openai({ apiKey: "k", fetch: r.fetch }).generate("x"), /OpenAI images 429: quota exceeded/);
  await assert.rejects(imagen({ apiKey: "k", fetch: r.fetch }).generate("x"), /Imagen 429/);
});

test("no key, no provider", () => {
  assert.equal(openai({ apiKey: "" }), null);
  assert.equal(ideogram({ apiKey: "" }), null);
});

test("photos go to OpenAI and text images to Ideogram, falling back to what is set", () => {
  const fake = (n) => () => ({ name: n });
  const all = { openai: fake("openai"), ideogram: fake("ideogram"), imagen: fake("imagen") };
  assert.equal(pickProvider("photo", { name: "auto", make: all }).name, "openai");
  assert.equal(pickProvider("text", { name: "auto", make: all }).name, "ideogram");
  const onlyGemini = { openai: () => null, ideogram: () => null, imagen: fake("imagen") };
  assert.equal(pickProvider("text", { name: "auto", make: onlyGemini }).name, "imagen");
  assert.equal(pickProvider("photo", { name: "auto", make: { openai: () => null, ideogram: () => null, imagen: () => null } }), null);
  assert.equal(pickProvider("photo", { name: "ideogram", make: all }).name, "ideogram");
  assert.throws(() => pickProvider("photo", { name: "openai", make: { ...all, openai: () => null } }), /no API key/);
  assert.throws(() => pickProvider("photo", { name: "dalle", make: all }), /unknown image provider/);
});

test("text images ask for the exact words; photos ask for no text", () => {
  assert.match(fullPrompt({ prompt: "A stone wall.", text: "Life is long" }), /"Life is long".*spelled exactly/);
  assert.ok(fullPrompt({ prompt: "A candle." }).endsWith(STYLE));
});

test("images are cached per provider and prompt", async () => {
  const cache = await mkdtemp(path.join(tmpdir(), "img-"));
  let n = 0;
  const p = { name: "openai", model: "m", generate: async () => { n++; return PNG; } };
  const a = await makeImage({ prompt: "a candle" }, { provider: p, cache });
  const b = await makeImage({ prompt: "a candle" }, { provider: p, cache });
  assert.equal(a, b);
  assert.equal(n, 1);
  assert.match(path.basename(a), /^openai-/);
  assert.deepEqual(await readFile(a), PNG);
  const c = await makeImage({ prompt: "a candle" }, { provider: { ...p, name: "ideogram" }, cache });
  assert.notEqual(c, a);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { openai, ideogram, imagen, pickProvider, makeImage, fullPrompt, imageKey, STYLE } from "../src/images.mjs";
import { authorization, r2FromEnv } from "../src/mediastore.mjs";

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
  assert.equal(body.quality, "medium");
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

const memoryStore = () => {
  const objects = new Map();
  return { objects, get: async (k) => objects.get(k) ?? null, put: async (k, b) => { objects.set(k, b); } };
};
const counting = (name = "openai") => {
  const p = { name, model: "m", size: "1024x1536", calls: 0, generate: async () => { p.calls++; return PNG; } };
  return p;
};

test("a generated image is saved locally and in the bucket, and never paid for twice", async () => {
  const cache = await mkdtemp(path.join(tmpdir(), "img-"));
  const store = memoryStore();
  const p = counting();
  const a = await makeImage({ prompt: "a candle" }, { provider: p, cache, store, regenerate: false });
  const b = await makeImage({ prompt: "a candle" }, { provider: p, cache, store, regenerate: false });
  assert.equal(a, b);
  assert.equal(p.calls, 1);
  assert.deepEqual(await readFile(a), PNG);
  assert.deepEqual([...store.objects.keys()], [imageKey(p, fullPrompt({ prompt: "a candle" }))]);
  assert.match(store.objects.keys().next().value, /^images\/openai-[0-9a-f]{24}\.png$/);
});

test("an image saved in the bucket is downloaded instead of regenerated", async () => {
  const store = memoryStore();
  const p = counting();
  await makeImage({ prompt: "a candle" }, { provider: p, cache: await mkdtemp(path.join(tmpdir(), "img-")), store, regenerate: false });
  // A fresh machine with an empty local cache.
  const file = await makeImage({ prompt: "a candle" }, { provider: p, cache: await mkdtemp(path.join(tmpdir(), "img-")), store, regenerate: false });
  assert.equal(p.calls, 1);
  assert.deepEqual(await readFile(file), PNG);
});

test("regenerating is explicit and replaces the saved copy", async () => {
  const cache = await mkdtemp(path.join(tmpdir(), "img-"));
  const store = memoryStore();
  const p = counting();
  await makeImage({ prompt: "a candle" }, { provider: p, cache, store, regenerate: false });
  await makeImage({ prompt: "a candle" }, { provider: p, cache, store, regenerate: true });
  assert.equal(p.calls, 2);
  assert.equal(store.objects.size, 1);
});

test("the key changes with provider, model, size and prompt", () => {
  const base = { name: "openai", model: "m", size: "1024x1536" };
  const k = imageKey(base, "p");
  assert.equal(imageKey({ ...base }, "p"), k);
  for (const other of [{ ...base, name: "ideogram" }, { ...base, model: "m2" }, { ...base, size: "1024x1024" }]) assert.notEqual(imageKey(other, "p"), k);
  assert.notEqual(imageKey(base, "q"), k);
});

test("R2 requests are signed with SigV4 (AWS's published example)", () => {
  const empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  const got = authorization({
    method: "GET", url: "https://examplebucket.s3.amazonaws.com/test.txt",
    headers: { range: "bytes=0-9", "x-amz-content-sha256": empty, "x-amz-date": "20130524T000000Z" },
    payloadHash: empty, accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    region: "us-east-1", amzDate: "20130524T000000Z",
  });
  assert.equal(got, "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " +
    "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " +
    "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41");
});

test("the R2 store puts and gets objects in the bucket", async () => {
  assert.equal(r2FromEnv({ env: {} }), null);
  const r = recorder((url, init) => init.method === "GET" ? (url.endsWith("missing.png") ? new Response("", { status: 404 }) : new Response(PNG)) : new Response(""));
  const store = r2FromEnv({ env: { R2_ACCOUNT_ID: "acct", R2_ACCESS_KEY_ID: "k", R2_SECRET_ACCESS_KEY: "s", R2_BUCKET: "media" }, fetch: r.fetch });
  await store.put("images/a.png", PNG);
  assert.equal(r.calls[0].url, "https://acct.r2.cloudflarestorage.com/media/images/a.png");
  assert.equal(r.calls[0].init.method, "PUT");
  assert.match(r.calls[0].init.headers.authorization, /^AWS4-HMAC-SHA256 Credential=k\/\d{8}\/auto\/s3\/aws4_request/);
  assert.deepEqual(await store.get("images/a.png"), PNG);
  assert.equal(await store.get("images/missing.png"), null);
});

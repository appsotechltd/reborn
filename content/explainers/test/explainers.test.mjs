import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { ROOT, loadCard, HEALTH_DISCLAIMER } from "../src/library.mjs";
import { buildTimeline, phrases, toVtt } from "../src/timeline.mjs";
import { narrate } from "../src/narration.mjs";
import { FilmPlan, checkPlan } from "../film/schema.mjs";

const scriptIds = async () => (await readdir(path.join(ROOT, "scripts"))).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5));

test("caption phrases stay short and never strand a single word", () => {
  for (const line of [
    "Steady daily effort beats bursts of talent followed by coasting. Here's the oldest proof we have.",
    "Pick one behaviour, track it daily, and add the next only once the first feels automatic.",
  ]) {
    const ps = phrases(line);
    assert.equal(ps.join(" "), line);
    for (const p of ps) {
      const n = p.split(" ").length;
      assert.ok(n <= 11 && n >= 3, `bad phrase "${p}"`);
    }
  }
});

test("timeline uses audio length when narrated and reading pace when silent", async () => {
  const card = await loadCard("aesops-fables--07");
  const scenes = [{ type: "title", narration: "One two three four five six seven eight nine ten." }, { type: "end", narration: "", min_seconds: 4 }];
  const silent = buildTimeline({ card, scenes, audio: [null, null] });
  const voiced = buildTimeline({ card, scenes, audio: [{ seconds: 9 }, null] });
  assert.ok(voiced.scenes[0].duration > silent.scenes[0].duration);
  assert.equal(voiced.scenes[1].start, voiced.scenes[0].duration);
  assert.equal(voiced.scenes[1].duration, 4);
  const cues = voiced.scenes[0].captions;
  assert.ok(Math.abs(cues.at(-1).end - (voiced.scenes[0].speechStart + 9)) < 0.01);
  assert.match(toVtt(voiced), /^WEBVTT\n\n1\n00:00:00\.350 --> /);
});

test("cards carry credit, licence and the health note for health cards", async () => {
  const health = await loadCard("nhs-breathing-exercises-for-stress--02");
  assert.equal(health.health, true);
  assert.equal(health.disclaimer, HEALTH_DISCLAIMER);
  assert.match(health.credit, /^Source: .*Open Government Licence/);
  const fable = await loadCard("aesops-fables--07");
  assert.equal(fable.disclaimer, null);
  assert.equal(fable.licenceName, "Public domain");
});

test("every script points at a real card and only uses known scene types", async () => {
  const scenesJs = await readFile(path.join(ROOT, "renderer", "scenes.js"), "utf8");
  const known = new Set([...scenesJs.matchAll(/R\.scenes\.(\w+) = /g)].map((m) => m[1]));
  for (const id of await scriptIds()) {
    const script = JSON.parse(await readFile(path.join(ROOT, "scripts", `${id}.json`), "utf8"));
    assert.equal(script.card_id, id);
    await loadCard(id);
    for (const s of script.scenes) assert.ok(known.has(s.type), `${id}: unknown scene ${s.type}`);
    assert.equal(script.scenes.at(-1).type, "end", `${id} must end on the credit card`);
  }
});

test("no narration provider means a silent render", async () => {
  assert.deepEqual(await narrate(null, "x--01", ["a", "", "b"]), [null, null, null]);
});

test("sample film plans are valid", async () => {
  const dir = path.join(ROOT, "film", "plans");
  for (const f of (await readdir(dir)).filter((x) => x.endsWith(".json"))) {
    const plan = FilmPlan.parse(JSON.parse(await readFile(path.join(dir, f), "utf8")));
    assert.deepEqual(checkPlan(plan, await loadCard(plan.card_id)), [], f);
  }
});

test("only approved voices can narrate", async () => {
  const { approvedVoice, VOICES, DEFAULT_VOICE } = await import("../src/voices.mjs");
  assert.equal(VOICES.length, 15);
  assert.ok(VOICES.includes(DEFAULT_VOICE));
  assert.deepEqual(approvedVoice("George"), { name: "george", engine: "kokoro", kokoroVoice: "bm_george" });
  assert.equal(approvedVoice("bella-chatterbox").engine, "chatterbox");
  for (const bad of ["af_heart", "fenrir", "nicole", "chatterbox", "elevenlabs"]) assert.throws(() => approvedVoice(bad), /not an approved voice/);
});

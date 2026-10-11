#!/usr/bin/env node
// Renders animated explainers for idea cards.
//
//   node src/render.mjs                         render every script in scripts/
//   node src/render.mjs aesops-fables--07       render one card
//   node src/render.mjs --stills                write a few PNG frames per card instead (fast preview)
//   node src/render.mjs --voice george          narrate in an approved voice (src/voices.mjs); "none" renders silent
//   node src/render.mjs --theme ember           render in a dark abstract theme (voltage, ember, aurora, swarm, depth)
//   node src/render.mjs --sample samples/seneca-photo.json   render a style sample to out/samples/
//   ... --image-provider openai|ideogram|imagen   force one image provider (default: picked per image)
//   ... --regenerate-images                       pay for new images instead of reusing the saved ones
//
// A script can set "voice" too; --voice wins. Videos have no captions (they hide the picture),
// on screen or as a caption track. Each render writes the .mp4 and a .jpg poster; upload both with
// `reborn media-upload content/explainers/out explainers`.
// Env: CHROMIUM_PATH points at a Chromium binary if Playwright's own is not installed.
import { readFile, writeFile, mkdir, rm, rename } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright-core";
import { ROOT, loadCard, listScripts } from "./library.mjs";
import { narrator, narrate } from "./narration.mjs";
import { buildTimeline } from "./timeline.mjs";
import { resolveImages } from "./images.mjs";

const SCRIPTS = path.join(ROOT, "scripts");
const OUT = path.join(ROOT, "out");
const RUNTIME = pathToFileURL(path.join(ROOT, "renderer", "runtime.html")).href;

function args() {
  const a = process.argv.slice(2);
  const opt = { ids: [], voice: undefined, stills: false };
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "--voice") opt.voice = a[++i];
    else if (a[i] === "--stills") opt.stills = true;
    else if (a[i] === "--theme") opt.theme = a[++i];
    else if (a[i] === "--image-provider") opt.imageProviderName = a[++i];
    else if (a[i] === "--regenerate-images") opt.regenerateImages = true;
    else if (a[i] === "--sample") opt.sample = a[++i];
    else opt.ids.push(a[i]);
  }
  return opt;
}

// undefined lets Playwright use the Chromium from `npx playwright-core install chromium`.
const chromiumPath = () => process.env.CHROMIUM_PATH || undefined;

function ffmpeg(argv, stdin = false) {
  const p = spawn("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...argv], { stdio: [stdin ? "pipe" : "ignore", "inherit", "inherit"] });
  const done = new Promise((res, rej) => p.on("close", (code) => (code === 0 ? res() : rej(new Error(`ffmpeg exited ${code}`)))));
  return { stdin: p.stdin, done };
}

/** Lays every scene's narration clip at its start time into one track. */
async function mixNarration(timeline, audio, file) {
  const clips = timeline.scenes.map((s, i) => ({ s, a: audio[i] })).filter((x) => x.a);
  const inputs = clips.flatMap((c) => ["-i", c.a.file]);
  const chains = clips.map((c, i) => `[${i}:a]adelay=${Math.round(c.s.speechStart * 1000)}:all=1[a${i}]`);
  const mix = `${clips.map((_, i) => `[a${i}]`).join("")}amix=inputs=${clips.length}:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100,apad,atrim=0:${timeline.duration}[out]`;
  await ffmpeg([...inputs, "-filter_complex", [...chains, mix].join(";"), "-map", "[out]", "-c:a", "aac", "-b:a", "128k", file]).done;
}

/** Composes music and sound effects for the edit (tools/score.py) and mixes them under the voice, ducking for speech. */
async function addScore(timeline, voiceFile, outFile, base) {
  const plan = {
    duration: timeline.duration,
    scenes: timeline.scenes.map((s) => ({ start: s.start, duration: s.duration, lift: Boolean(s.params.lift) })),
    beats: timeline.scenes.flatMap((s) => (s.beats || []).map((b) => ({ at: b.start }))),
    seed: 1,
  };
  await writeFile(`${base}.score.json`, JSON.stringify(plan));
  await new Promise((res, rej) => {
    const p = spawn(process.env.PYTHON || "python3", [path.join(ROOT, "tools", "score.py"), `${base}.score.json`, `${base}.score.wav`], { stdio: "inherit" });
    p.on("close", (code) => (code === 0 ? res() : rej(new Error(`score.py exited ${code}`))));
  });
  const tmp = `${base}.mix.m4a`;
  const graph = voiceFile
    ? `[0:a]aformat=channel_layouts=stereo,asplit=2[v][key];[1:a]volume=0.5[m];[m][key]sidechaincompress=threshold=0.04:ratio=5:attack=30:release=500[duck];[v][duck]amix=inputs=2:normalize=0,loudnorm=I=-14:TP=-1:LRA=11,aresample=44100,apad,atrim=0:${timeline.duration}[out]`
    : `[0:a]loudnorm=I=-16:TP=-1:LRA=11,aresample=44100,apad,atrim=0:${timeline.duration}[out]`;
  const inputs = voiceFile ? ["-i", voiceFile, "-i", `${base}.score.wav`] : ["-i", `${base}.score.wav`];
  await ffmpeg([...inputs, "-filter_complex", graph, "-map", "[out]", "-c:a", "aac", "-b:a", "160k", tmp]).done;
  await rename(tmp, outFile);
  await rm(`${base}.score.json`, { force: true });
  await rm(`${base}.score.wav`, { force: true });
}

async function renderCard(browser, cardId, opt) {
  const script = JSON.parse(await readFile(path.join(SCRIPTS, `${cardId}.json`), "utf8"));
  const card = await loadCard(script.card_id || cardId);
  const entry = await renderScenes(browser, card, script.scenes, { ...opt, voice: opt.voice ?? script.voice, label: cardId, base: path.join(OUT, card.id), fps: script.fps, theme: opt.theme || script.theme,
    captionMax: script.captionMax, score: script.score });
  return entry && { ...entry, script: `scripts/${cardId}.json` };
}

/**
 * Renders scenes for a card to `${opt.base}.mp4` and its `.jpg` poster.
 * Also used by the film pipeline to render its end card.
 */
export async function renderScenes(browser, card, scenes, opt) {
  const cardId = opt.label || card.id;
  const provider = opt.provider !== undefined ? opt.provider : narrator(opt.voice);
  const audio = await narrate(provider, card.id, scenes.map((s) => s.narration || ""));
  await resolveImages(scenes, { provider: opt.imageProvider, providerName: opt.imageProviderName, regenerate: opt.regenerateImages });
  const timeline = { ...buildTimeline({ card, scenes, audio, fps: opt.fps || 30, captionMax: opt.captionMax }), theme: opt.theme || null };

  const page = await browser.newPage({ viewport: { width: timeline.width, height: timeline.height }, deviceScaleFactor: timeline.scale });
  page.on("pageerror", (e) => console.error(`[${cardId}] page error:`, e.message));
  await page.goto(RUNTIME);
  await page.evaluate((tl) => window.__setup(tl), timeline);

  if (opt.stills) {
    const dir = path.join(ROOT, ".cache", "stills", cardId);
    await rm(dir, { recursive: true, force: true });
    await mkdir(dir, { recursive: true });
    for (const s of timeline.scenes) {
      for (const f of [0.55, 0.9]) {
        const t = s.start + s.duration * f;
        await page.evaluate((x) => window.__seek(x), t);
        await page.screenshot({ path: path.join(dir, `${t.toFixed(1).padStart(5, "0")}-${s.type}.png`) });
      }
    }
    await page.close();
    console.log(`${cardId}: stills in ${path.relative(process.cwd(), dir)}`);
    return null;
  }

  const base = opt.base;
  await mkdir(path.dirname(base), { recursive: true });
  const narrationFile = `${base}.narration.m4a`;
  if (provider) await mixNarration(timeline, audio, narrationFile);
  if (opt.score) await addScore(timeline, provider ? narrationFile : null, narrationFile, base);
  const hasAudio = Boolean(provider || opt.score);

  const frames = Math.ceil(timeline.duration * timeline.fps);
  const enc = ffmpeg([
    "-f", "image2pipe", "-framerate", String(timeline.fps), "-c:v", "mjpeg", "-i", "-",
    ...(hasAudio ? ["-i", narrationFile, "-map", "0:v", "-map", "1:a", "-c:a", "copy"] : []),
    "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-profile:v", "high",
    "-vf", "scale=720:1280:flags=lanczos", "-movflags", "+faststart", "-t", String(timeline.duration), `${base}.mp4`,
  ], true);
  const started = Date.now();
  for (let i = 0; i < frames; i++) {
    await page.evaluate((x) => window.__seek(x), i / timeline.fps);
    const jpg = await page.screenshot({ type: "jpeg", quality: 92 });
    if (!enc.stdin.write(jpg)) await new Promise((r) => enc.stdin.once("drain", r));
    if (i % 150 === 0) process.stdout.write(`\r${cardId}: frame ${i}/${frames}`);
  }
  enc.stdin.end();
  await enc.done;
  if (hasAudio) await rm(narrationFile, { force: true });

  // Poster: the title scene once the title has landed.
  await page.evaluate((x) => window.__seek(x), Math.min(timeline.scenes[0].duration - 0.6, 3.2));
  await page.screenshot({ path: `${base}.jpg`, type: "jpeg", quality: 85, scale: "css" });
  await page.close();
  for (const ext of ["mp4", "jpg"]) if (!existsSync(`${base}.${ext}`)) throw new Error(`${cardId}: ${base}.${ext} was not written`);
  console.log(`\r${cardId}: ${timeline.duration.toFixed(1)}s, ${frames} frames in ${((Date.now() - started) / 1000).toFixed(0)}s${provider ? `, narrated (${provider.name})` : ", silent"}`);

  return {
    video: `${path.basename(base)}.mp4`,
    poster: `${path.basename(base)}.jpg`,
    duration_s: Math.round(timeline.duration * 10) / 10,
    width: 720,
    height: 1280,
    narrated: Boolean(provider),
    voice: provider ? provider.voice : null,
    kind: "animated",
  };
}

export function launchBrowser() {
  return chromium.launch({ executablePath: chromiumPath() });
}

/** Renders a style sample (samples/*.json) to out/samples/, leaving the card's own video alone. */
async function renderSample(file, opt) {
  const script = JSON.parse(await readFile(file, "utf8"));
  const card = await loadCard(script.card_id);
  const browser = await launchBrowser();
  try {
    await renderScenes(browser, card, script.scenes, { ...opt, voice: opt.voice ?? script.voice, label: path.basename(file, ".json"),
      base: path.join(OUT, "samples", path.basename(file, ".json")), fps: script.fps, theme: opt.theme || script.theme,
      captionMax: script.captionMax, score: script.score });
  } finally {
    await browser.close();
  }
}

async function main() {
  const opt = args();
  if (opt.sample) return renderSample(opt.sample, opt);
  const ids = opt.ids.length ? opt.ids : await listScripts(SCRIPTS);
  const manifestFile = path.join(OUT, "manifest.json");
  const manifest = existsSync(manifestFile) ? JSON.parse(await readFile(manifestFile, "utf8")) : { version: 1, explainers: {} };
  const browser = await launchBrowser();
  try {
    for (const id of ids) {
      const entry = await renderCard(browser, id, opt);
      if (entry) manifest.explainers[id] = entry;
    }
  } finally {
    await browser.close();
  }
  if (!opt.stills) {
    manifest.explainers = Object.fromEntries(Object.entries(manifest.explainers).sort(([a], [b]) => a.localeCompare(b)));
    await writeFile(manifestFile, JSON.stringify(manifest, null, 2) + "\n");
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(e); process.exit(1); });

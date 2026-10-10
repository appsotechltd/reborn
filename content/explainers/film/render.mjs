#!/usr/bin/env node
// Renders a realistic short film from a reviewed plan in film/plans/.
//
//   node film/render.mjs aesops-fables--07 --dry-run     print the prompts and length, spend nothing
//   FILM_PROVIDER=veo GEMINI_API_KEY=... node film/render.mjs aesops-fables--07
//   node film/render.mjs aesops-fables--07 --provider animatic   free placeholder clips to preview pacing
//   ... --publish                                        make the film the card's explainer in out/manifest.json
//
// Each shot is generated once and cached by provider + prompt, so editing one
// shot only re-renders that shot. Narration uses the same provider as the
// animated explainers (ElevenLabs when ELEVENLABS_API_KEY is set). Captions,
// the source credit and any health note are burned in, and the film ends on
// the same end card as the animated explainers.
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";
import { ROOT, loadCard } from "../src/library.mjs";
import { narrator, narrate } from "../src/narration.mjs";
import { phrases, wordCount } from "../src/timeline.mjs";
import { launchBrowser, renderScenes } from "../src/render.mjs";
import { FilmPlan, checkPlan } from "./schema.mjs";
import { videoProvider } from "./providers/index.mjs";

const OUT = path.join(ROOT, "out");
const END_CARD_SECONDS = 4;
const W = 720, H = 1280;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function ffmpeg(argv) {
  const p = spawn("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...argv], { stdio: ["ignore", "inherit", "inherit"] });
  return new Promise((res, rej) => p.on("close", (c) => (c === 0 ? res() : rej(new Error(`ffmpeg exited ${c}`)))));
}

async function generateShot(provider, plan, shot, dir) {
  const prompt = `${shot.prompt}\n\nStyle: ${plan.style}. ${shot.framing}, ${shot.camera}. Vertical 9:16, no on-screen text.`;
  const seconds = Math.min(provider.clipSeconds[1], Math.max(provider.clipSeconds[0], shot.seconds));
  const key = createHash("sha256").update(JSON.stringify([provider.name, provider.model, prompt, plan.negative_prompt, seconds])).digest("hex").slice(0, 12);
  const file = path.join(dir, `${shot.id}-${key}.mp4`);
  if (existsSync(file)) return file;
  console.log(`  ${shot.id}: generating ${seconds}s on ${provider.name}...`);
  const job = await provider.start({ prompt, negativePrompt: plan.negative_prompt, seconds, aspectRatio: "9:16" });
  const deadline = Date.now() + 20 * 60 * 1000;
  for (;;) {
    if (Date.now() > deadline) throw new Error(`${shot.id}: timed out waiting for ${provider.name}`);
    if (provider.name !== "animatic") await sleep(10_000);
    const r = await provider.poll(job);
    if (!r.done) continue;
    if (r.file) {
      await copyFile(r.file, file);
      return file;
    }
    const res = await fetch(r.url, { headers: r.headers });
    if (!res.ok) throw new Error(`${shot.id}: download failed ${res.status}`);
    await writeFile(file, Buffer.from(await res.arrayBuffer()));
    return file;
  }
}

const assTime = (s) => {
  const cs = Math.round(s * 100);
  return `${Math.floor(cs / 360000)}:${String(Math.floor(cs / 6000) % 60).padStart(2, "0")}:${String(Math.floor(cs / 100) % 60).padStart(2, "0")}.${String(cs % 100).padStart(2, "0")}`;
};
const assText = (s) => s.replace(/[{}]/g, "").replace(/\n/g, "\\N");

/** Captions at the bottom, the source credit (and health note) at the top. */
function subtitles(card, cues, filmSeconds) {
  const lines = [
    "[Script Info]", "ScriptType: v4.00+", `PlayResX: ${W}`, `PlayResY: ${H}`, "WrapStyle: 0", "",
    "[V4+ Styles]",
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
    "Style: Caption,Inter,40,&H00F3FAFF,&H00F3FAFF,&H00000000,&H50201A16,1,0,0,0,100,100,0,0,3,14,0,2,60,60,230,1",
    "Style: Credit,Inter,20,&H00F3FAFF,&H00F3FAFF,&H00000000,&H78000000,0,0,0,0,100,100,0,0,3,8,0,8,40,40,40,1",
    "Style: Health,Inter,22,&H0008475C,&H0008475C,&H00000000,&H00D6F4FF,1,0,0,0,100,100,0,0,3,8,0,8,40,40,96,1",
    "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    `Dialogue: 0,${assTime(0)},${assTime(filmSeconds)},Credit,,0,0,0,,${assText(`From ${card.sourceTitle} · ${card.authors.join(", ")} · ${card.licenceName}`)}`,
  ];
  if (card.health) lines.push(`Dialogue: 0,${assTime(0)},${assTime(filmSeconds)},Health,,0,0,0,,General information, not medical advice.`);
  for (const c of cues) lines.push(`Dialogue: 1,${assTime(c.start)},${assTime(c.end)},Caption,,0,0,0,,${assText(c.text)}`);
  return lines.join("\n") + "\n";
}

async function renderFilm(cardId, opt) {
  const card = await loadCard(cardId);
  const plan = FilmPlan.parse(JSON.parse(await readFile(path.join(ROOT, "film", "plans", `${cardId}.json`), "utf8")));
  const problems = checkPlan(plan, card);
  if (problems.length) throw new Error(`${cardId}: fix the plan first:\n  ${problems.join("\n  ")}`);
  const filmSeconds = plan.shots.reduce((n, s) => n + s.seconds, 0);

  if (opt.dryRun) {
    console.log(`${cardId}: ${plan.shots.length} shots, ${filmSeconds}s + ${END_CARD_SECONDS}s end card\n  ${plan.logline}\n  style: ${plan.style}`);
    for (const s of plan.shots) console.log(`\n  [${s.id}] ${s.seconds}s, ${s.framing}, ${s.camera}\n  prompt: ${s.prompt}\n  voice:  ${s.narration || "(silence)"}`);
    return null;
  }

  const provider = videoProvider(opt.provider);
  const dir = path.join(ROOT, ".cache", "film", cardId);
  await mkdir(dir, { recursive: true });

  // 1. Clips, normalised to 720x1280 @ 30fps, trimmed to the planned length, silent.
  const norm = [];
  for (const shot of plan.shots) {
    const raw = await generateShot(provider, plan, shot, dir);
    const out = raw.replace(/\.mp4$/, `.norm${shot.seconds}.mp4`);
    if (!existsSync(out)) {
      await ffmpeg(["-i", raw, "-t", String(shot.seconds), "-an",
        "-vf", `scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},fps=30,setsar=1`,
        "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", out]);
    }
    norm.push(out);
  }

  // 2. End card from the animated renderer, so films and explainers close the same way.
  const browser = await launchBrowser();
  const endBase = path.join(dir, "endcard");
  try {
    await renderScenes(browser, card, [{ type: "end", narration: "", min_seconds: END_CARD_SECONDS }], { voice: "none", base: endBase, label: `${cardId} end card` });
  } finally {
    await browser.close();
  }

  // 3. Narration and captions, each shot's line starting just after its cut.
  const voice = narrator(opt.voice);
  const audio = await narrate(voice, `${cardId}-film`, plan.shots.map((s) => s.narration));
  const cues = [];
  let t = 0;
  const delays = [];
  plan.shots.forEach((s, i) => {
    const start = t + 0.3;
    const words = wordCount(s.narration);
    const speech = audio[i]?.seconds ?? words / 2.6;
    if (words) {
      let c = start;
      for (const p of phrases(s.narration)) {
        const len = (wordCount(p) / words) * speech;
        cues.push({ start: c, end: c + len, text: p });
        c += len;
      }
    }
    if (audio[i]) delays.push({ file: audio[i].file, ms: Math.round(start * 1000) });
    t += s.seconds;
  });
  const assFile = path.join(dir, "captions.ass");
  await writeFile(assFile, subtitles(card, cues, filmSeconds));

  // 4. Assemble: shots + end card, burn in captions/credit, lay narration over.
  const inputs = [...norm, `${endBase}.mp4`].flatMap((f) => ["-i", f]);
  const n = norm.length + 1;
  const audioInputs = delays.flatMap((d) => ["-i", d.file]);
  const total = filmSeconds + END_CARD_SECONDS;
  const filters = [
    `${Array.from({ length: n }, (_, i) => `[${i}:v]`).join("")}concat=n=${n}:v=1:a=0[cat]`,
    `[cat]subtitles=${assFile.replace(/:/g, "\\:")}:fontsdir=${path.join(ROOT, "renderer", "fonts")}[v]`,
  ];
  const maps = ["-map", "[v]"];
  if (delays.length) {
    delays.forEach((d, i) => filters.push(`[${n + i}:a]adelay=${d.ms}:all=1[a${i}]`));
    filters.push(`${delays.map((_, i) => `[a${i}]`).join("")}amix=inputs=${delays.length}:normalize=0,apad,atrim=0:${total}[aout]`);
    maps.push("-map", "[aout]", "-c:a", "aac", "-b:a", "128k");
  }
  const base = path.join(OUT, `${cardId}.film`);
  await ffmpeg([...inputs, ...audioInputs, "-filter_complex", filters.join(";"), ...maps,
    "-c:v", "libx264", "-preset", "slow", "-crf", "22", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-t", String(total), `${base}.mp4`]);
  await ffmpeg(["-ss", String(Math.min(2, plan.shots[0].seconds / 2)), "-i", `${base}.mp4`, "-frames:v", "1", "-q:v", "3", `${base}.jpg`]);
  const vtt = (s) => new Date(s * 1000).toISOString().slice(11, 23);
  await writeFile(`${base}.vtt`, "WEBVTT\n\n" + cues.map((c, i) => `${i + 1}\n${vtt(c.start)} --> ${vtt(c.end)}\n${c.text}\n`).join("\n"));
  console.log(`${cardId}: film ${total}s -> ${path.relative(process.cwd(), base)}.mp4`);

  return {
    kind: "film", video: `${cardId}.film.mp4`, poster: `${cardId}.film.jpg`, captions: `${cardId}.film.vtt`,
    duration_s: total, width: W, height: H, narrated: Boolean(voice), voice: voice?.voice ?? null,
    provider: `${provider.name}/${provider.model}`, plan: `film/plans/${cardId}.json`,
  };
}

async function main() {
  const a = process.argv.slice(2);
  const opt = { ids: [], dryRun: false, publish: false, provider: undefined, voice: undefined };
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "--dry-run") opt.dryRun = true;
    else if (a[i] === "--publish") opt.publish = true;
    else if (a[i] === "--provider") opt.provider = a[++i];
    else if (a[i] === "--voice") opt.voice = a[++i];
    else opt.ids.push(a[i]);
  }
  if (!opt.ids.length) {
    console.error("usage: node film/render.mjs <card-id> [...] [--dry-run] [--provider veo|runway] [--voice elevenlabs|none] [--publish]");
    process.exit(2);
  }
  const manifestFile = path.join(OUT, "manifest.json");
  for (const id of opt.ids) {
    const entry = await renderFilm(id, opt);
    if (entry && opt.publish) {
      const manifest = existsSync(manifestFile) ? JSON.parse(await readFile(manifestFile, "utf8")) : { version: 1, explainers: {} };
      manifest.explainers[id] = entry;
      await writeFile(manifestFile, JSON.stringify(manifest, null, 2) + "\n");
      console.log(`${id}: published the film as the card's explainer`);
    }
  }
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });

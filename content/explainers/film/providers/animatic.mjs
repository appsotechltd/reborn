// A free stand-in provider: renders each shot as a plain card showing its
// framing and prompt, so a plan's pacing, captions and narration can be
// previewed before paying for real footage.
import { spawn } from "node:child_process";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const run = (argv) => new Promise((res, rej) => {
  const p = spawn("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...argv], { stdio: ["ignore", "inherit", "inherit"] });
  p.on("close", (c) => (c === 0 ? res() : rej(new Error(`ffmpeg exited ${c}`))));
});

const wrap = (text, width = 34) => text.split(/\s+/).reduce((lines, w) => {
  const last = lines[lines.length - 1];
  if (last && (last + " " + w).length <= width) lines[lines.length - 1] = last + " " + w;
  else lines.push(w);
  return lines;
}, []).slice(0, 12).join("\n");

export function animatic() {
  return {
    name: "animatic",
    model: "ffmpeg",
    clipSeconds: [1, 10],
    async start({ prompt, seconds }) {
      const dir = await mkdtemp(path.join(tmpdir(), "animatic-"));
      const file = path.join(dir, "clip.mp4");
      const text = wrap(prompt.split("\n")[0]).replace(/[\\:'%]/g, "");
      await run(["-f", "lavfi", "-i", `color=c=0x3d342d:s=720x1280:d=${seconds}:r=30`,
        "-vf", `drawtext=text='${text}':fontcolor=0xf6efe6:fontsize=30:line_spacing=10:x=(w-text_w)/2:y=(h-text_h)/2-120`,
        "-c:v", "libx264", "-pix_fmt", "yuv420p", file]);
      return file;
    },
    async poll(file) {
      return { done: true, file };
    },
  };
}

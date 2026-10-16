/* "Photo": cinematic stills with slow camera moves, crossfades, drifting dust, light and grain.
 *
 * A scene (or a beat inside it) sets params.image = { src } (the render resolves prompts to files).
 * Each image holds until the next one; zoom: "out" pulls back instead of pushing in.
 * An image can set fx / fy (0-1) to keep that point of the picture in frame when it is cropped,
 * and credit (a line shown small above the footer while the picture is up, for CC BY photos).
 */
(function () {
  const R = window.R;
  const TAU = Math.PI * 2;
  const FADE = 0.7;

  function photo(tl) {
    const W = R.bg.W, H = R.bg.H, wide = W > H;
    const shots = [];
    tl.scenes.forEach((s) => {
      if (s.params.image) shots.push({ start: s.start, image: s.params.image, zoom: s.params.zoom });
      for (const b of s.beats || []) if (b.image) shots.push({ start: b.start, image: b.image, zoom: b.zoom });
    });
    shots.forEach((sh, i) => { sh.end = shots[i + 1] ? shots[i + 1].start + FADE : tl.duration; sh.pan = i % 2 ? 1 : -1; });
    const imgs = new Map();
    const ready = Promise.all(shots.map((sh) => new Promise((res, rej) => {
      if (imgs.has(sh.image.src)) return res();
      const im = new Image();
      im.onload = () => res(); im.onerror = () => rej(new Error(`could not load ${sh.image.src}`));
      im.src = sh.image.src;
      imgs.set(sh.image.src, im);
    })));
    const rnd = R.rng(5);
    const motes = Array.from({ length: 90 }, () => ({ x: rnd() * W, y: rnd() * H, r: 0.6 + rnd() * 2.2, v: 4 + rnd() * 14, ph: rnd() * TAU, f: 0.3 + rnd() }));

    function drawShot(g, sh, t, alpha) {
      const im = imgs.get(sh.image.src);
      if (!im || !im.width) return;
      const p = R.clamp((t - sh.start) / Math.max(1, sh.end - sh.start));
      const e = R.ease(p) * 0.6 + p * 0.4;
      const z = sh.zoom === "out" ? R.lerp(1.26, 1.06, e) : R.lerp(1.06, 1.24, e);
      // A wide frame shows a portrait still whole; a landscape picture (a space photo) fills it.
      if (wide && im.width / im.height < 1.2) return drawWide(g, im, sh, e, alpha);
      const cover = Math.max(W / im.width, H / im.height) * z;
      const w = im.width * cover, h = im.height * cover;
      const fx = sh.image.fx ?? 0.5, fy = sh.image.fy ?? 0.5;
      const x = R.clamp(W / 2 - w * fx, W - w, 0) + sh.pan * R.lerp(-14, 14, e);
      const y = R.clamp(H / 2 - h * fy, H - h, 0) + R.lerp(8, -10, e);
      g.globalAlpha = alpha;
      g.drawImage(im, x, y, w, h);
      g.globalAlpha = 1;
    }

    // A wide frame keeps the whole (portrait) still in view, so nothing in it is cut off: sharp at
    // the frame's height in the middle, its sides melting into a blurred, dimmed copy that fills the
    // width.
    const off = wide ? document.createElement("canvas") : null;
    function drawWide(g, im, sh, e, alpha) {
      const s = g.getTransform().a;
      g.globalAlpha = alpha;
      const cover = Math.max(W / im.width, H / im.height) * R.lerp(1.08, 1.16, e);
      const bw = im.width * cover, bh = im.height * cover;
      g.filter = "blur(26px) brightness(0.5) saturate(1.1)";
      g.drawImage(im, (W - bw) / 2 + sh.pan * R.lerp(-24, 24, e), (H - bh) / 2, bw, bh);
      g.filter = "none";

      const fit = (H / im.height) * (sh.zoom === "out" ? R.lerp(1.12, 1.0, e) : R.lerp(1.0, 1.12, e));
      const w = im.width * fit, h = im.height * fit;
      const x = (W - w) / 2 + sh.pan * R.lerp(-8, 8, e), y = (H - h) / 2 + R.lerp(4, -4, e);
      if (off.width !== Math.round(W * s)) { off.width = Math.round(W * s); off.height = Math.round(H * s); }
      const o = off.getContext("2d");
      o.setTransform(s, 0, 0, s, 0, 0);
      o.globalCompositeOperation = "source-over";
      o.clearRect(0, 0, W, H);
      o.drawImage(im, x, y, w, h);
      o.globalCompositeOperation = "destination-in";
      const f = Math.min(80, w * 0.22) / w;
      const mask = o.createLinearGradient(x, 0, x + w, 0);
      mask.addColorStop(0, "rgba(0,0,0,0)"); mask.addColorStop(f, "#000"); mask.addColorStop(1 - f, "#000"); mask.addColorStop(1, "rgba(0,0,0,0)");
      o.fillStyle = mask; o.fillRect(0, 0, W, H);
      o.globalCompositeOperation = "source-over";
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.drawImage(off, 0, 0);
      g.setTransform(s, 0, 0, s, 0, 0);
      g.globalAlpha = 1;
    }

    function draw(g, t, energy) {
      g.fillStyle = "#000"; g.fillRect(0, 0, W, H);
      let k = -1;
      for (let i = 0; i < shots.length; i++) if (t >= shots[i].start) k = i;
      if (k >= 0) {
        const cur = shots[k];
        const fadeIn = k > 0 ? R.ease(R.seg(t - cur.start, 0, FADE)) : R.ease(R.seg(t, 0, 1.2));
        if (k > 0 && fadeIn < 1) drawShot(g, shots[k - 1], t, 1);
        drawShot(g, cur, t, fadeIn);
      }
      // The end card needs a quiet backdrop for the credit: fade the picture down under it.
      const end = tl.scenes.find((s) => s.type === "end");
      if (end && t > end.start - 0.4) { g.fillStyle = `rgba(0,0,0,${(0.72 * R.ease(R.seg(t, end.start - 0.4, end.start + 0.6))).toFixed(3)})`; g.fillRect(0, 0, W, H); }
      // Grade: darken a touch, deepen the bottom for the credit.
      g.fillStyle = "rgba(0,0,0,0.12)"; g.fillRect(0, 0, W, H);
      const low = g.createLinearGradient(0, H * 0.5, 0, H);
      low.addColorStop(0, "rgba(0,0,0,0)"); low.addColorStop(1, "rgba(0,0,0,0.78)");
      g.fillStyle = low; g.fillRect(0, H * 0.5, W, H * 0.5);
      g.globalCompositeOperation = "lighter";
      // A warm light leak that blooms on each cut.
      const lx = W * (0.8 + 0.15 * Math.sin(t * 0.2)), ly = H * (0.12 + 0.05 * Math.cos(t * 0.17));
      const leak = g.createRadialGradient(lx, ly, 0, lx, ly, 420);
      leak.addColorStop(0, `rgba(255,150,70,${(0.06 + 0.16 * energy).toFixed(3)})`); leak.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = leak; g.fillRect(0, 0, W, H);
      // Dust drifting through the light.
      for (const m of motes) {
        const x = (m.x + Math.sin(t * m.f + m.ph) * 20 + W) % W, y = (m.y - t * m.v + H * 10) % H;
        const a = 0.12 + 0.18 * Math.abs(Math.sin(t * m.f * 2 + m.ph));
        g.fillStyle = `rgba(255,230,200,${a.toFixed(3)})`;
        g.beginPath(); g.arc(x, y, m.r, 0, TAU); g.fill();
      }
      g.globalCompositeOperation = "source-over";
      const v = g.createRadialGradient(W / 2, H * 0.42, H * 0.25, W / 2, H * 0.42, H * 0.8);
      v.addColorStop(0, "rgba(0,0,0,0)"); v.addColorStop(1, "rgba(0,0,0,0.6)");
      g.fillStyle = v; g.fillRect(0, 0, W, H);
      const gr = R.rng(Math.floor(t * 30) + 7);
      for (let n = 0; n < 1600; n++) {
        g.fillStyle = gr() < 0.5 ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.1)";
        g.fillRect(gr() * W, gr() * H, 1.2, 1.2);
      }
    }
    // The picture's credit (CC BY photos must carry one), small above the footer, up to two lines.
    function drawCredit(g, sh, alpha) {
      if (!sh || !sh.image.credit || alpha <= 0) return;
      const text = `Image: ${sh.image.credit}`;
      g.save();
      g.globalAlpha = 0.75 * alpha;
      g.fillStyle = "#e9e1d6";
      g.textAlign = "center";
      g.textBaseline = "alphabetic";
      g.font = "10px \"Reborn Sans\", sans-serif";
      const max = W - 64;
      const lines = [];
      let line = "";
      for (const word of text.split(" ")) {
        const next = line ? `${line} ${word}` : word;
        if (g.measureText(next).width > max && line) { lines.push(line); line = word; } else line = next;
      }
      lines.push(line);
      const base = H - (wide ? 52 : 70);
      lines.slice(0, 3).forEach((l, i, all) => g.fillText(l, W / 2, base - (all.length - 1 - i) * 12));
      g.restore();
    }
    const plain = draw;
    function drawWithCredit(g, t, energy) {
      plain(g, t, energy);
      const end = tl.scenes.find((s) => s.type === "end");
      if (end && t > end.start - 0.4) return;
      let k = -1;
      for (let i = 0; i < shots.length; i++) if (t >= shots[i].start) k = i;
      if (k < 0) return;
      const fadeIn = k > 0 ? R.ease(R.seg(t - shots[k].start, 0, FADE)) : 1;
      if (k > 0 && fadeIn < 1) drawCredit(g, shots[k - 1], 1 - fadeIn);
      drawCredit(g, shots[k], fadeIn);
    }
    drawWithCredit.ready = ready;
    return drawWithCredit;
  }

  R.bg.register("photo", photo);
})();

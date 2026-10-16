/* "Photo": cinematic stills with slow camera moves, crossfades, drifting dust, light and grain.
 *
 * A scene (or a beat inside it) sets params.image = { src } (the render resolves prompts to files).
 * Each image holds until the next one; zoom: "out" pulls back instead of pushing in.
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
      const cover = Math.max(W / im.width, H / im.height) * z;
      const w = im.width * cover, h = im.height * cover;
      // A wide frame shows a band of the (portrait) still, so it tilts slowly through it instead.
      const x = (W - w) / 2 + sh.pan * R.lerp(-14, 14, e);
      const y = wide ? R.lerp(-0.12, 0.12, sh.pan > 0 ? e : 1 - e) * (h - H) + (H - h) / 2 : (H - h) / 2 + R.lerp(8, -10, e);
      g.globalAlpha = alpha;
      g.drawImage(im, x, y, w, h);
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
    draw.ready = ready;
    return draw;
  }

  R.bg.register("photo", photo);
})();

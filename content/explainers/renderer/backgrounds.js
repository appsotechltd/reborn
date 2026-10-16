/* Abstract animated backgrounds for the dark themes.
 *
 * Each painter draws one frame onto a canvas as a pure function of time t, like
 * the scenes: positions come from closed-form motion and seeded randomness, never
 * from the previous frame. `energy` rises to 1 at each scene change and decays,
 * so the background answers the edit.
 */
(function () {
  const R = window.R;
  // The stage size: 540x960 (portrait) or 960x540 (landscape), set by R.bg.setup.
  let W = 540, H = 960;
  const TAU = Math.PI * 2;

  const pick = (seed) => { const r = R.rng(seed); r(); return r; };
  const rgba = (rgb, a) => `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${R.clamp(a).toFixed(3)})`;

  function glow(g, x, y, r, rgb, a) {
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, rgba(rgb, a));
    grad.addColorStop(1, rgba(rgb, 0));
    g.fillStyle = grad;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  }

  /** A jagged bolt from a to b by midpoint displacement. */
  function bolt(rnd, ax, ay, bx, by, spread, depth) {
    let pts = [[ax, ay], [bx, by]];
    for (let d = 0; d < depth; d++) {
      const next = [pts[0]];
      for (let i = 1; i < pts.length; i++) {
        const [x0, y0] = pts[i - 1], [x1, y1] = pts[i];
        const len = Math.hypot(x1 - x0, y1 - y0);
        const nx = -(y1 - y0) / (len || 1), ny = (x1 - x0) / (len || 1);
        const off = (rnd() - 0.5) * spread * len;
        next.push([(x0 + x1) / 2 + nx * off, (y0 + y1) / 2 + ny * off], pts[i]);
      }
      pts = next;
    }
    return pts;
  }
  function strokePath(g, pts) {
    g.beginPath();
    g.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) g.lineTo(pts[i][0], pts[i][1]);
    g.stroke();
  }

  // ---------- Voltage: circuit traces carrying pulses, lightning on every cut ----------
  function voltage() {
    const rnd = pick(7);
    const CYAN = [111, 233, 255], VIOLET = [150, 95, 255], WHITE = [235, 250, 255];
    // Manhattan traces that run in from the edges.
    const traces = Array.from({ length: 26 }, () => {
      const pts = [];
      let x = rnd() < 0.5 ? -10 : W + 10, y = 60 + rnd() * (H - 120);
      const dir = x < 0 ? 1 : -1;
      pts.push([x, y]);
      const steps = 3 + Math.floor(rnd() * 4);
      for (let s = 0; s < steps; s++) {
        x += dir * (40 + rnd() * 110); pts.push([x, y]);
        y += (rnd() < 0.5 ? -1 : 1) * (30 + rnd() * 120); pts.push([x, y]);
      }
      let len = 0;
      const cum = [0];
      for (let i = 1; i < pts.length; i++) { len += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); cum.push(len); }
      return { pts, cum, len, speed: 90 + rnd() * 160, off: rnd() * 10, col: rnd() < 0.7 ? CYAN : VIOLET };
    });
    const at = (tr, d) => {
      d = R.clamp(d, 0, tr.len);
      let i = 1;
      while (i < tr.cum.length - 1 && tr.cum[i] < d) i++;
      const k = (d - tr.cum[i - 1]) / (tr.cum[i] - tr.cum[i - 1] || 1);
      return [R.lerp(tr.pts[i - 1][0], tr.pts[i][0], k), R.lerp(tr.pts[i - 1][1], tr.pts[i][1], k)];
    };

    return function draw(g, t, energy, cuts) {
      g.fillStyle = "#03040b";
      g.fillRect(0, 0, W, H);
      glow(g, W * 0.5 + Math.sin(t * 0.21) * 60, H * 0.38 + Math.cos(t * 0.17) * 50, 460, [20, 40, 120], 0.55 + 0.25 * energy);
      glow(g, W * 0.15 + Math.cos(t * 0.13) * 40, H * 0.85, 360, [60, 20, 120], 0.45);

      g.globalCompositeOperation = "lighter";
      g.lineCap = "round"; g.lineJoin = "round";
      // Faint traces with solder pads.
      for (const tr of traces) {
        g.strokeStyle = rgba(tr.col, 0.07 + 0.06 * energy); g.lineWidth = 1.2;
        strokePath(g, tr.pts);
        const end = tr.pts[tr.pts.length - 1];
        g.fillStyle = rgba(tr.col, 0.18); g.beginPath(); g.arc(end[0], end[1], 2.5, 0, TAU); g.fill();
      }
      // Pulses travelling along them, with a comet tail.
      for (const tr of traces) {
        const period = tr.len / tr.speed + 1.5;
        const d = (((t + tr.off) % period) / period) * (tr.len + 120);
        for (let k = 0; k < 8; k++) {
          const p = at(tr, d - k * 9);
          const a = (1 - k / 8) * (0.55 + 0.45 * energy);
          if (d - k * 9 < 0 || d - k * 9 > tr.len) continue;
          glow(g, p[0], p[1], 10 - k * 0.8, tr.col, a * 0.5);
          if (k === 0) { g.fillStyle = rgba(WHITE, a); g.beginPath(); g.arc(p[0], p[1], 1.8, 0, TAU); g.fill(); }
        }
      }
      // Lightning: a strike at every scene change, plus an occasional ambient arc.
      const strikes = cuts.map((c, i) => ({ at: c, seed: 100 + i, big: true }));
      for (let b = Math.floor(t / 2.7) - 1; b <= Math.floor(t / 2.7); b++) {
        if (b < 0) continue;
        const r = pick(900 + b);
        strikes.push({ at: b * 2.7 + r() * 2, seed: 2000 + b, big: false });
      }
      for (const s of strikes) {
        const age = t - s.at;
        const life = s.big ? 0.55 : 0.3;
        if (age < 0 || age > life) continue;
        const flick = Math.floor(age * 24);
        const r = pick(s.seed * 31 + flick);
        const sr = pick(s.seed);
        const ax = 40 + sr() * (W - 80), bx = 40 + sr() * (W - 80);
        const ay = s.big ? -20 : 80 + sr() * 300, by = s.big ? H + 20 : ay + 160 + sr() * 260;
        const pts = bolt(r, ax, ay, bx, by, 0.45, 7);
        const fade = (1 - age / life) * (0.6 + 0.4 * Math.abs(Math.sin(age * 60)));
        g.strokeStyle = rgba(VIOLET, fade * (s.big ? 0.35 : 0.2)); g.lineWidth = s.big ? 14 : 8; strokePath(g, pts);
        g.strokeStyle = rgba(CYAN, fade * 0.6); g.lineWidth = s.big ? 4 : 2.5; strokePath(g, pts);
        g.strokeStyle = rgba(WHITE, fade * 0.95); g.lineWidth = s.big ? 1.6 : 1; strokePath(g, pts);
        if (s.big) {
          // A branch splitting off partway down.
          const from = pts[Math.floor(pts.length * (0.3 + sr() * 0.3))];
          const br = bolt(r, from[0], from[1], from[0] + (sr() - 0.5) * 300, from[1] + 120 + sr() * 200, 0.5, 5);
          g.strokeStyle = rgba(CYAN, fade * 0.4); g.lineWidth = 2; strokePath(g, br);
          g.globalCompositeOperation = "source-over";
          g.fillStyle = rgba([180, 200, 255], fade * 0.08); g.fillRect(0, 0, W, H);
          g.globalCompositeOperation = "lighter";
        }
      }
      g.globalCompositeOperation = "source-over";
      // Scan lines for a little texture.
      g.fillStyle = "rgba(0,0,0,0.18)";
      for (let y = 0; y < H; y += 4) g.fillRect(0, y, W, 1);
    };
  }

  // ---------- Ember: molten light, rising sparks, slow smoke-like glows ----------
  function ember() {
    const rnd = pick(21);
    const sparks = Array.from({ length: 170 }, () => ({
      x: rnd() * W, v: 22 + rnd() * 70, off: rnd() * 2000, w: 0.4 + rnd() * 1.2, ph: rnd() * TAU,
      amp: 10 + rnd() * 40, size: 0.6 + rnd() * rnd() * 2.6, flick: 3 + rnd() * 9, hot: rnd(),
    }));
    const bokeh = Array.from({ length: 14 }, () => ({ x: rnd() * W, y: rnd() * H, r: 30 + rnd() * 70, s: 0.05 + rnd() * 0.12, ph: rnd() * TAU }));
    const GOLD = [245, 181, 74], ORANGE = [255, 110, 40], RED = [170, 30, 20];
    const pos = (s, t) => {
      const span = H + 80;
      const y = H + 40 - ((t * s.v + s.off) % span);
      const x = s.x + Math.sin(t * s.w + s.ph) * s.amp + Math.sin(t * 0.37 + y * 0.01) * 18;
      return [x, y];
    };
    return function draw(g, t, energy) {
      g.fillStyle = "#090403";
      g.fillRect(0, 0, W, H);
      // Molten pools of light drifting under everything.
      glow(g, W * 0.5 + Math.sin(t * 0.15) * 90, H * 1.02, 560, RED, 0.7 + 0.2 * energy);
      glow(g, W * 0.2 + Math.cos(t * 0.11) * 70, H * 0.3 + Math.sin(t * 0.09) * 80, 380, [90, 30, 10], 0.55);
      glow(g, W * 0.85 + Math.sin(t * 0.12) * 50, H * 0.55 + Math.cos(t * 0.1) * 90, 330, [120, 60, 10], 0.45);

      g.globalCompositeOperation = "lighter";
      for (const b of bokeh) {
        const y = (b.y - t * 14 * b.s * 10 + H * 4) % (H + 200) - 100;
        glow(g, b.x + Math.sin(t * b.s + b.ph) * 30, y, b.r, GOLD, 0.05 + 0.03 * Math.sin(t * 0.7 + b.ph));
      }
      g.lineCap = "round";
      for (const s of sparks) {
        const [x, y] = pos(s, t);
        const [px, py] = pos(s, t - 0.09);
        if (Math.abs(py - y) > 100) continue; // wrapped this frame
        const heat = R.clamp(y / H); // hotter near the bottom
        const col = s.hot > 0.6 ? GOLD : ORANGE;
        const a = (0.35 + 0.65 * Math.abs(Math.sin(t * s.flick + s.ph))) * (0.35 + 0.65 * heat) * (0.75 + 0.5 * energy);
        g.strokeStyle = rgba(col, a); g.lineWidth = s.size;
        g.beginPath(); g.moveTo(px, py); g.lineTo(x, y); g.stroke();
        if (s.size > 1.6) glow(g, x, y, s.size * 7, col, a * 0.35);
      }
      g.globalCompositeOperation = "source-over";
      // Vignette.
      const v = g.createRadialGradient(W / 2, H * 0.45, H * 0.25, W / 2, H * 0.45, H * 0.75);
      v.addColorStop(0, "rgba(0,0,0,0)"); v.addColorStop(1, "rgba(0,0,0,0.65)");
      g.fillStyle = v; g.fillRect(0, 0, W, H);
    };
  }

  // ---------- Aurora: curtains of light over a deep starfield ----------
  function aurora() {
    const rnd = pick(33);
    const stars = Array.from({ length: 150 }, () => ({ x: rnd() * W, y: rnd() * H, r: 0.3 + rnd() * 1.1, tw: 0.5 + rnd() * 3, ph: rnd() * TAU }));
    const MAGENTA = [255, 70, 170], TEAL = [50, 235, 205], VIOLET = [120, 80, 255];
    const ribbons = [
      { y: 0.22, amp: 70, k: 0.011, s: 0.35, col: TEAL, h: 140 },
      { y: 0.42, amp: 90, k: 0.008, s: -0.27, col: MAGENTA, h: 170 },
      { y: 0.66, amp: 60, k: 0.013, s: 0.22, col: VIOLET, h: 120 },
      { y: 0.84, amp: 80, k: 0.009, s: -0.31, col: TEAL, h: 110 },
    ];
    return function draw(g, t, energy) {
      const bg = g.createLinearGradient(0, 0, 0, H);
      bg.addColorStop(0, "#04021a"); bg.addColorStop(0.6, "#070321"); bg.addColorStop(1, "#02010c");
      g.fillStyle = bg; g.fillRect(0, 0, W, H);
      for (const s of stars) {
        const a = 0.25 + 0.6 * Math.abs(Math.sin(t * s.tw + s.ph));
        g.fillStyle = `rgba(230,235,255,${a.toFixed(3)})`;
        g.beginPath(); g.arc(s.x, s.y, s.r, 0, TAU); g.fill();
      }
      g.globalCompositeOperation = "lighter";
      ribbons.forEach((rb, ri) => {
        const base = rb.y * H;
        const yAt = (x) => base + Math.sin(x * rb.k + t * rb.s + ri) * rb.amp + Math.sin(x * rb.k * 2.3 - t * rb.s * 1.7) * rb.amp * 0.35;
        // A curtain: vertical rays rising from the ribbon's edge, brightest at the edge.
        for (let x = -10; x <= W + 10; x += 3) {
          const y = yAt(x);
          const pulse = 0.5 + 0.5 * Math.sin(x * 0.045 - t * 1.6 + ri * 2);
          const h = rb.h * (0.55 + 0.45 * pulse);
          const a = (0.1 + 0.16 * pulse) * (0.8 + 0.6 * energy);
          const gr = g.createLinearGradient(0, y - h, 0, y);
          gr.addColorStop(0, rgba(rb.col, 0)); gr.addColorStop(1, rgba(rb.col, a));
          g.fillStyle = gr; g.fillRect(x, y - h, 3, h);
        }
        g.strokeStyle = rgba(rb.col, 0.35 + 0.25 * energy); g.lineWidth = 1.5;
        g.beginPath();
        for (let x = -10; x <= W + 10; x += 6) { const y = yAt(x); x < 0 ? g.moveTo(x, y) : g.lineTo(x, y); }
        g.stroke();
      });
      g.globalCompositeOperation = "source-over";
      const v = g.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, H * 0.8);
      v.addColorStop(0, "rgba(0,0,0,0)"); v.addColorStop(1, "rgba(0,0,0,0.55)");
      g.fillStyle = v; g.fillRect(0, 0, W, H);
    };
  }

  const painters = { voltage, ember, aurora };
  let draw = null, g = null, cuts = [];

  R.bg = {
    themes: Object.keys(painters),
    W: 540,
    H: 960,
    // Looks that lay themselves out for any stage size (the others assume 540x960).
    landscape: new Set(["voltage", "ember", "aurora", "photo"]),
    register(name, factory) { painters[name] = factory; R.bg.themes = Object.keys(painters); },
    setup(canvas, theme, sceneStarts, scale, tl) {
      draw = null;
      R.bg.ready = Promise.resolve();
      W = R.bg.W = tl?.width || 540;
      H = R.bg.H = tl?.height || 960;
      if (W > H && painters[theme] && !R.bg.landscape.has(theme)) throw new Error(`the ${theme} look has no landscape layout yet`);
      canvas.hidden = !painters[theme];
      if (!painters[theme]) return;
      canvas.width = W * scale; canvas.height = H * scale;
      g = canvas.getContext("2d");
      g.setTransform(scale, 0, 0, scale, 0, 0);
      cuts = sceneStarts;
      draw = painters[theme](tl);
      R.bg.ready = draw.ready || Promise.resolve();
    },
    draw(t) {
      if (!draw) return;
      let energy = 0;
      for (const c of cuts) if (t >= c) energy = Math.max(energy, Math.exp(-(t - c) * 2.2));
      draw(g, t, energy, cuts);
    },
  };
})();

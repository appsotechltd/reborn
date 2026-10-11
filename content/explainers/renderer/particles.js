/* "Swarm": a field of glowing particles that gathers into a shape for each scene.
 *
 * A scene names its shape in params.shape:
 *   { text: "SHORT?", size: 150 }          letters
 *   { draw: "hourglass" | "target" | "ring" | "heart" | "path", d, stroke, fill }
 *   absent                                  particles drift as a loose nebula
 * params.leak (0..1) makes that share of the particles break away from the shape
 * during the scene. Like every painter, a frame is a pure function of time.
 */
(function () {
  const R = window.R;
  const W = 540, H = 960, N = 1500, CX = 270, CY = 330;
  const TAU = Math.PI * 2;
  const MORPH = 1.5; // seconds to fly from one shape to the next

  const builtins = {
    hourglass(g) {
      g.lineWidth = 9; g.lineJoin = "round";
      g.beginPath();
      g.moveTo(170, 150); g.lineTo(370, 150);
      g.bezierCurveTo(370, 250, 285, 290, 285, 330); g.bezierCurveTo(285, 370, 370, 410, 370, 510);
      g.lineTo(170, 510);
      g.bezierCurveTo(170, 410, 255, 370, 255, 330); g.bezierCurveTo(255, 290, 170, 250, 170, 150);
      g.stroke();
      g.beginPath(); g.moveTo(195, 505); g.quadraticCurveTo(270, 430, 345, 505); g.closePath(); g.fill(); // sand below
      g.beginPath(); g.moveTo(205, 205); g.lineTo(335, 205); g.quadraticCurveTo(300, 260, 270, 285); g.quadraticCurveTo(240, 260, 205, 205); g.fill(); // sand above
    },
    target(g) {
      g.lineWidth = 8;
      for (const r of [165, 110, 55]) { g.beginPath(); g.arc(CX, CY, r, 0, TAU); g.stroke(); }
      g.beginPath(); g.arc(CX, CY, 16, 0, TAU); g.fill();
    },
    ring(g) { g.lineWidth = 12; g.beginPath(); g.arc(CX, CY, 150, 0, TAU); g.stroke(); },
    heart(g) {
      g.beginPath(); g.moveTo(CX, 480);
      g.bezierCurveTo(60, 340, 140, 150, CX, 250); g.bezierCurveTo(400, 150, 480, 340, CX, 480); g.fill();
    },
  };

  /** Samples N points from a shape drawn white on an offscreen canvas. */
  function sample(shape, seed, count = N) {
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    const g = c.getContext("2d");
    g.fillStyle = g.strokeStyle = "#fff";
    if (shape.text) {
      const lines = String(shape.text).split("\n");
      const size = shape.size || 140;
      g.font = `800 ${size}px "Reborn Sans", sans-serif`;
      g.textAlign = "center"; g.textBaseline = "middle";
      lines.forEach((l, i) => g.fillText(l, CX, CY + (i - (lines.length - 1) / 2) * size * 1.05));
    } else if (shape.draw === "path") {
      const p = new Path2D(shape.d);
      g.save(); g.translate(shape.x ?? 0, shape.y ?? 0); g.scale(shape.scale ?? 1, shape.scale ?? 1);
      g.lineWidth = shape.stroke ?? 8; g.lineJoin = g.lineCap = "round";
      if (shape.fill) g.fill(p); else g.stroke(p);
      g.restore();
    } else if (builtins[shape.draw]) builtins[shape.draw](g);
    const data = g.getImageData(0, 0, W, H).data;
    const lit = [];
    for (let y = 0; y < H; y += 2) for (let x = 0; x < W; x += 2) if (data[(y * W + x) * 4 + 3] > 128) lit.push([x, y]);
    const rnd = R.rng(seed);
    const pts = Array.from({ length: count }, () => (lit.length ? lit[Math.floor(rnd() * lit.length)] : [CX, CY]).map((v) => v + rnd() * 2 - 1));
    // Sort by angle around the centre so neighbours stay neighbours between shapes: morphs swirl instead of scrambling.
    return pts.sort((a, b) => Math.atan2(a[1] - CY, a[0] - CX) - Math.atan2(b[1] - CY, b[0] - CX));
  }

  function swarm(tl) {
    const rnd = R.rng(77);
    const P = Array.from({ length: N }, () => ({ ph: rnd() * TAU, f: 0.6 + rnd() * 1.6, r: 0.6 + rnd() * rnd() * 1.9,
      delay: rnd() * 0.45, orbit: 60 + rnd() * 330, w: (rnd() < 0.5 ? -1 : 1) * (0.05 + rnd() * 0.12), esc: rnd(), escAng: rnd() * TAU,
      hue: rnd() }));
    const COLS = [[205, 225, 255], [130, 200, 255], [170, 140, 255], [255, 255, 255]];
    let targets = null;
    const nebula = (p, t) => [CX + Math.cos(p.ph + t * p.w) * p.orbit, CY + 60 + Math.sin(p.ph + t * p.w) * p.orbit * 1.35];

    return function draw(g, t, energy) {
      if (!targets) targets = tl.scenes.map((s, i) => (s.params.shape ? sample(s.params.shape, 500 + i) : null));
      let k = 0;
      while (k < tl.scenes.length - 1 && t >= tl.scenes[k + 1].start) k++;
      const sc = tl.scenes[k];

      const bg = g.createRadialGradient(CX, CY, 40, CX, CY, H * 0.9);
      bg.addColorStop(0, "#0b0d24"); bg.addColorStop(1, "#010108");
      g.fillStyle = bg; g.fillRect(0, 0, W, H);

      g.globalCompositeOperation = "lighter";
      for (let i = 0; i < N; i++) {
        const p = P[i];
        const at = (j, tt) => (targets[j] ? targets[j][i] : nebula(p, tt));
        const local = t - sc.start;
        const m = R.ease(R.seg(local, p.delay, p.delay + MORPH));
        const from = k > 0 ? at(k - 1, t) : nebula(p, t);
        const to = at(k, t);
        // Curve the flight path sideways so the swarm swirls between shapes.
        const dx = to[0] - from[0], dy = to[1] - from[1];
        const bend = Math.sin(m * Math.PI) * 0.25 * (i % 2 ? 1 : -1);
        let x = from[0] + dx * m - dy * bend;
        let y = from[1] + dy * m + dx * bend;
        // Shimmer while holding a shape.
        x += Math.sin(t * p.f * 2 + p.ph) * 1.6; y += Math.cos(t * p.f * 1.7 + p.ph) * 1.6;
        let a = 0.55 + 0.45 * Math.sin(t * p.f + p.ph);
        const leak = sc.params.leak || 0;
        if (targets[k] && p.esc < leak) {
          // This particle breaks away partway through the scene and drifts off, fading.
          const te = sc.start + 1.8 + (p.esc / leak) * (sc.duration - 2.6);
          const e = Math.max(0, t - te);
          if (e > 0) {
            x += Math.cos(p.escAng) * e * 70 + Math.sin(e * 2 + p.ph) * 10;
            y += Math.sin(p.escAng) * e * 50 + e * e * 18;
            a *= Math.max(0, 1 - e / 2.5);
          }
        }
        if (!targets[k]) a *= 0.45; // a dim nebula behind text scenes
        if (a <= 0.01) continue;
        const c = COLS[Math.floor(p.hue * COLS.length)];
        a = R.clamp(a * (0.85 + 0.4 * energy));
        g.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${(a * 0.18).toFixed(3)})`;
        g.beginPath(); g.arc(x, y, p.r * 3.2, 0, TAU); g.fill();
        g.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${a.toFixed(3)})`;
        g.fillRect(x - p.r / 2, y - p.r / 2, p.r, p.r);
      }
      g.globalCompositeOperation = "source-over";
    };
  }

  R.sampleShape = sample;
  R.bg.register("swarm", swarm);
})();

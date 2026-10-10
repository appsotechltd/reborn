/* "Depth": 3D particle objects that turn in space and re-form for each scene.
 *
 * A scene names its object in params.object:
 *   { kind: "sphere" | "hourglass" | "torus" | "helix" | "cube" | "rings" | "text", text, size }
 *   absent  particles drift as a slow 3D galaxy behind text
 * params.leak (0..1) makes that share of the particles break off and fall away.
 * Points are projected with a simple perspective camera on a 2D canvas, so the
 * frame stays a pure function of time and needs no WebGL.
 */
(function () {
  const R = window.R;
  const W = 540, H = 960, N = 1700, CX = 270, CY = 330;
  const TAU = Math.PI * 2;
  const MORPH = 1.6, FOCAL = 620, DIST = 760;

  function object(spec, seed) {
    const rnd = R.rng(seed);
    const pts = [];
    const kind = spec.kind;
    for (let i = 0; i < N; i++) {
      const u = rnd(), v = rnd();
      if (kind === "sphere") {
        const y = 1 - (i / (N - 1)) * 2, r = Math.sqrt(1 - y * y), a = i * 2.39996;
        pts.push([Math.cos(a) * r * 160, y * 160, Math.sin(a) * r * 160]);
      } else if (kind === "hourglass") {
        // A glass surface of revolution, with sand heaped in the lower bulb.
        if (i < N * 0.62) {
          // Spread points evenly over the surface: wide bulbs get more than the narrow neck.
          let y, r;
          do { y = (rnd() * 2 - 1) * 185; r = 14 + 120 * Math.pow(Math.abs(y) / 185, 1.25); } while (rnd() > r / 134);
          const a = v * TAU;
          pts.push([Math.cos(a) * r, y, Math.sin(a) * r]);
        } else {
          const h = Math.sqrt(u) * 70, a = v * TAU;
          const y = 182 - h, r = (1 - h / 70) * 118 * Math.sqrt(rnd());
          pts.push([Math.cos(a) * r, y, Math.sin(a) * r]);
        }
      } else if (kind === "torus") {
        const a = u * TAU, b = v * TAU;
        pts.push([(140 + 45 * Math.cos(b)) * Math.cos(a), 45 * Math.sin(b), (140 + 45 * Math.cos(b)) * Math.sin(a)]);
      } else if (kind === "helix") {
        const k = i % 2, s = (i / N) * 2 - 1, a = s * TAU * 2.2 + k * Math.PI;
        if (i % 9 === 0) { const w = rnd() * 2 - 1, a2 = Math.floor(s * 22) / 22 * TAU * 2.2; pts.push([Math.cos(a2) * 80 * w, s * 210, Math.sin(a2) * 80 * w]); }
        else pts.push([Math.cos(a) * 80 + rnd() * 4, s * 210, Math.sin(a) * 80 + rnd() * 4]);
      } else if (kind === "cube") {
        const f = Math.floor(rnd() * 12), t = rnd() * 2 - 1, s = 120;
        const e = [[t, -1, -1], [t, 1, -1], [t, -1, 1], [t, 1, 1], [-1, t, -1], [1, t, -1], [-1, t, 1], [1, t, 1], [-1, -1, t], [1, -1, t], [-1, 1, t], [1, 1, t]][f];
        pts.push(e.map((c) => c * s + (rnd() - 0.5) * 5));
      } else if (kind === "rings") {
        // Three tilted orbits around a bright core: attention aimed at a few things.
        const ring = i % 4;
        if (ring === 3) { const r = Math.cbrt(u) * 34, a = v * TAU, b = Math.acos(rnd() * 2 - 1); pts.push([r * Math.sin(b) * Math.cos(a), r * Math.cos(b), r * Math.sin(b) * Math.sin(a)]); }
        else {
          const a = u * TAU, rr = 110 + ring * 45, tilt = [0.3, -0.7, 1.2][ring];
          const x = Math.cos(a) * rr, z = Math.sin(a) * rr;
          pts.push([x, z * Math.sin(tilt) + (rnd() - 0.5) * 4, z * Math.cos(tilt)]);
        }
      } else if (kind === "text") {
        if (!R.sampleShape) throw new Error("depth text needs particles.js");
        const flat = R.sampleShape({ text: spec.text, size: spec.size }, seed, N);
        return flat.map(([x, y]) => [x - CX, y - CY, (rnd() - 0.5) * 30]);
      } else {
        pts.push([0, 0, 0]);
      }
    }
    return pts;
  }

  function depth(tl) {
    const rnd = R.rng(99);
    const P = Array.from({ length: N }, () => ({ ph: rnd() * TAU, f: 0.5 + rnd() * 1.5, r: 0.7 + rnd() * rnd() * 1.6,
      delay: rnd() * 0.5, esc: rnd(), ex: rnd() * 2 - 1, ez: rnd() * 2 - 1,
      gr: 80 + rnd() * 380, ga: rnd() * TAU, gy: (rnd() - 0.5) * 120 * rnd() }));
    let shots = null;
    const galaxy = (p, t) => { const a = p.ga + t * (40 / p.gr); return [Math.cos(a) * p.gr, p.gy, Math.sin(a) * p.gr]; };
    const NEAR = [255, 214, 150], FAR = [70, 120, 255];

    return function draw(g, t, energy) {
      if (!shots) {
        // A shot per scene, plus one per beat: the object re-forms on a word of the narration.
        shots = [];
        tl.scenes.forEach((s) => {
          shots.push({ start: s.start, object: s.params.object, leak: s.params.leak, zoom: s.params.zoom });
          for (const b of s.beats || []) shots.push({ start: b.start, object: b.object, leak: b.leak, zoom: b.zoom });
        });
        shots.forEach((sh, i) => { sh.end = shots[i + 1] ? shots[i + 1].start : tl.duration; sh.pts = sh.object ? object(sh.object, 700 + i) : null; });
      }
      let k = 0;
      while (k < shots.length - 1 && t >= shots[k + 1].start) k++;
      const sc = shots[k];
      sc.duration = sc.end - sc.start;

      const bg = g.createLinearGradient(0, 0, 0, H);
      bg.addColorStop(0, "#020208"); bg.addColorStop(0.45, "#07081a"); bg.addColorStop(1, "#010104");
      g.fillStyle = bg; g.fillRect(0, 0, W, H);
      // Nebula clouds: slow, colourful depth behind everything.
      g.globalCompositeOperation = "lighter";
      for (const [x, y, r, c, sp] of [[0.2, 0.25, 360, [20, 70, 120], 0.07], [0.85, 0.5, 400, [90, 40, 20], 0.05], [0.4, 0.8, 380, [40, 20, 90], 0.06], [0.7, 0.15, 260, [10, 90, 100], 0.08]]) {
        const gx = W * x + Math.sin(t * sp + r) * 50, gy = H * y + Math.cos(t * sp * 1.3 + r) * 40;
        const gr = g.createRadialGradient(gx, gy, 0, gx, gy, r);
        gr.addColorStop(0, `rgba(${c[0]},${c[1]},${c[2]},${(0.32 + 0.15 * energy).toFixed(3)})`); gr.addColorStop(1, "rgba(0,0,0,0)");
        g.fillStyle = gr; g.fillRect(gx - r, gy - r, r * 2, r * 2);
      }
      g.globalCompositeOperation = "source-over";
      // Slow camera push-in through each shot (or pull-out when a shot asks for it).
      const push = R.ease(R.seg(t - sc.start, 0, sc.duration));
      const zoom = sc.zoom === "out" ? R.lerp(1.25, 0.95, push) : R.lerp(0.95, 1.18, push);

      const yaw = t * 0.45, pitch = 0.32 + Math.sin(t * 0.23) * 0.12;
      const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
      const project = (x, y, z) => {
        const x1 = x * cy - z * sy, z1 = x * sy + z * cy;
        const y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
        const s = (FOCAL * zoom) / (DIST + z2);
        return [CX + x1 * s, CY + y2 * s, z2, s];
      };

      g.globalCompositeOperation = "lighter";
      // A dotted floor turning with the object, for a sense of space.
      for (let gx = -6; gx <= 6; gx++) for (let gz = -6; gz <= 6; gz++) {
        const [x, y, z, s] = project(gx * 60, 250, gz * 60);
        const a = R.clamp(0.35 - (z + 300) / 2600) * (1 - Math.hypot(gx, gz) / 9);
        if (a <= 0) continue;
        g.fillStyle = `rgba(110,150,255,${a.toFixed(3)})`;
        g.fillRect(x - s, y - s * 0.5, s * 2, s);
      }

      for (let i = 0; i < N; i++) {
        const p = P[i];
        const at = (j) => {
          if (!shots[j].pts) return galaxy(p, t);
          if (shots[j].object.kind !== "text") return shots[j].pts[i];
          // Words stay readable: cancel the camera's spin and just sway a little.
          const [ox, oy, oz] = shots[j].pts[i], r = yaw + Math.sin(t * 0.6) * 0.25;
          return [ox * Math.cos(r) + oz * Math.sin(r), oy, -ox * Math.sin(r) + oz * Math.cos(r)];
        };
        const m = R.ease(R.seg(t - sc.start, p.delay, p.delay + MORPH));
        const A = k > 0 ? at(k - 1) : galaxy(p, t), B = at(k);
        // Fly along an arc that bulges outward, so shapes burst and re-form.
        const bulge = 1 + Math.sin(m * Math.PI) * 0.45;
        let x = R.lerp(A[0], B[0], m) * bulge, y = R.lerp(A[1], B[1], m) * bulge, z = R.lerp(A[2], B[2], m) * bulge;
        x += Math.sin(t * p.f + p.ph) * 1.5; y += Math.cos(t * p.f * 1.3 + p.ph) * 1.5;
        let a = 1;
        const leak = sc.leak || 0;
        if (sc.pts && p.esc < leak) {
          const te = sc.start + 1.8 + (p.esc / leak) * (sc.duration - 2.6);
          const e = Math.max(0, t - te);
          if (e > 0) { x += p.ex * e * 60; z += p.ez * e * 60; y += e * e * 40; a = Math.max(0, 1 - e / 2.8); }
        }
        if (!sc.pts) a *= 0.5;
        const [sx, sy2, z2, s] = project(x, y, z);
        const near = R.clamp(0.5 - z2 / 420); // 1 = close to the camera
        const c = [0, 1, 2].map((j) => Math.round(R.lerp(FAR[j], NEAR[j], near)));
        a = R.clamp(a * (0.25 + 0.75 * near) * (0.75 + 0.35 * Math.sin(t * p.f + p.ph) ** 2) * (0.9 + 0.4 * energy));
        if (a <= 0.01) continue;
        const r = p.r * s * 1.1;
        g.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${(a * 0.16).toFixed(3)})`;
        g.beginPath(); g.arc(sx, sy2, r * 3.4, 0, TAU); g.fill();
        g.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${a.toFixed(3)})`;
        g.beginPath(); g.arc(sx, sy2, r * 0.75, 0, TAU); g.fill();
      }
      g.globalCompositeOperation = "source-over";
      // Film finish: vignette and a fresh grain pattern every frame.
      const v = g.createRadialGradient(CX, H * 0.42, H * 0.22, CX, H * 0.42, H * 0.78);
      v.addColorStop(0, "rgba(0,0,0,0)"); v.addColorStop(1, "rgba(0,0,0,0.7)");
      g.fillStyle = v; g.fillRect(0, 0, W, H);
      const gr = R.rng(Math.floor(t * 30) + 1);
      for (let n = 0; n < 1400; n++) {
        g.fillStyle = gr() < 0.5 ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.09)";
        g.fillRect(gr() * W, gr() * H, 1.2, 1.2);
      }
    };
  }

  R.bg.register("depth", depth);
})();

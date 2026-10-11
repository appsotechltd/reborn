/* Scene library for Reborn explainers.
 *
 * Every scene type has setup(node, ctx) -> state, called once, and
 * update(node, t, ctx, state), called every frame with the scene-local time t
 * (0..ctx.duration). ctx = { card, params, duration, index }.
 *
 * Coordinates are in the 540x960 stage. The illustration band is y 100-710;
 * the source credit sits below it, so scenes keep their content above y 710.
 * Illustrations are original drawings: no book covers or copyrighted imagery.
 */
(function () {
  const R = (window.R = {});

  // ---------- helpers ----------
  R.clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
  R.lerp = (a, b, p) => a + (b - a) * p;
  R.seg = (t, a, b) => (b <= a ? (t >= b ? 1 : 0) : R.clamp((t - a) / (b - a)));
  R.easeOut = (p) => 1 - Math.pow(1 - p, 3);
  R.easeIn = (p) => p * p * p;
  R.ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
  R.back = (p) => { const c = 1.6; return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); };
  R.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  R.rng = (seed) => () => { // mulberry32: deterministic "randomness"
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let x = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  R.words = (text, cls = "word") => String(text).split(/\s+/).filter(Boolean)
    .map((w) => `<span class="${cls}">${R.esc(w)}</span>`).join(" ");
  const reveal = (nodes, t, start, step, dur = 0.55, rise = 16) => {
    nodes.forEach((n, i) => {
      const p = R.easeOut(R.seg(t, start + i * step, start + i * step + dur));
      n.style.opacity = p.toFixed(3);
      n.style.transform = `translateY(${((1 - p) * rise).toFixed(2)}px)`;
    });
  };
  const fadeIn = (n, t, a, b) => { const p = R.easeOut(R.seg(t, a, b)); n.style.opacity = p.toFixed(3); return p; };
  const svgBand = (inner, top = 100, h = 600) =>
    `<svg width="540" height="${h}" viewBox="0 0 540 ${h}" style="position:absolute;left:0;top:${top}px">${inner}</svg>`;

  R.scenes = {};

  // ---------- title ----------
  R.scenes.title = {
    setup(node, { card, params }) {
      node.innerHTML = `
        <div class="blob" style="position:absolute;width:420px;height:420px;border-radius:50%;background:var(--accent-soft);left:-120px;top:120px;opacity:.55"></div>
        <div class="blob" style="position:absolute;width:300px;height:300px;border-radius:50%;background:#e4ecdc;right:-110px;top:470px;opacity:.6"></div>
        <div class="center" style="top:100px;height:610px;justify-content:center;gap:22px">
          <div class="eyebrow">${R.esc(params.eyebrow || "One idea · one minute")}</div>
          <h1 class="serif t" style="font-size:${card.title.length > 60 ? 36 : 41}px;line-height:1.14;font-weight:600;letter-spacing:-0.01em">${R.words(card.title)}</h1>
          <div class="rule" style="height:3px;width:0;background:var(--accent);border-radius:2px"></div>
          <div class="src" style="font-size:16px;color:var(--muted)">From <i class="serif" style="font-size:18px;color:var(--ink)">${R.esc(card.sourceTitle)}</i><br>${R.esc(card.authors.join(", "))}</div>
        </div>`;
      return { eyebrow: node.querySelector(".eyebrow"), words: [...node.querySelectorAll(".t .word")],
        rule: node.querySelector(".rule"), src: node.querySelector(".src"), blobs: [...node.querySelectorAll(".blob")] };
    },
    update(node, t, ctx, s) {
      fadeIn(s.eyebrow, t, 0.1, 0.7);
      reveal(s.words, t, 0.35, 0.07);
      const rp = R.easeOut(R.seg(t, 0.9 + s.words.length * 0.07, 1.6 + s.words.length * 0.07));
      s.rule.style.width = `${(rp * 90).toFixed(1)}px`;
      fadeIn(s.src, t, 1.2 + s.words.length * 0.07, 2.0 + s.words.length * 0.07);
      s.blobs[0].style.transform = `translate(${Math.sin(t * 0.35) * 18}px, ${Math.cos(t * 0.3) * 14}px) scale(${1 + t * 0.01})`;
      s.blobs[1].style.transform = `translate(${Math.cos(t * 0.4) * 14}px, ${Math.sin(t * 0.33) * 16}px)`;
    },
  };

  // ---------- statement: kinetic lines, optional emphasis and strike-through ----------
  R.scenes.statement = {
    setup(node, { params }) {
      const lines = params.lines || [];
      const emph = new Set(params.emphasis || []);
      const size = params.size || 34;
      node.innerHTML = `
        <div class="center" style="top:100px;height:610px;justify-content:center;gap:${params.gap ?? 18}px">
          ${params.kicker ? `<div class="eyebrow kicker">${R.esc(params.kicker)}</div>` : ""}
          ${lines.map((l, i) => `
            <div class="line serif" style="position:relative;font-size:${emph.has(i) ? size + 4 : size}px;line-height:1.18;font-weight:${emph.has(i) ? 700 : 500};color:${emph.has(i) ? "var(--accent)" : "var(--ink)"}">
              ${R.esc(l)}${params.strike === i ? `<div class="strike" style="position:absolute;left:-6px;top:52%;height:4px;width:0;background:var(--accent);border-radius:2px"></div>` : ""}
            </div>`).join("")}
        </div>`;
      return { lines: [...node.querySelectorAll(".line")], kicker: node.querySelector(".kicker"), strike: node.querySelector(".strike") };
    },
    update(node, t, { params, duration }, s) {
      if (s.kicker) fadeIn(s.kicker, t, 0, 0.5);
      const stagger = params.stagger ?? Math.min(1.1, (duration * 0.6) / Math.max(1, s.lines.length));
      reveal(s.lines, t, 0.2, stagger, 0.7, 22);
      if (s.strike) {
        const at = params.strikeAt ?? duration * 0.4;
        const p = R.easeOut(R.seg(t, at, at + 0.5));
        const line = s.lines[params.strike];
        s.strike.style.width = `${(p * (line.offsetWidth + 12)).toFixed(1)}px`;
        line.style.color = p > 0 ? "var(--muted)" : "";
      }
    },
  };

  // ---------- quote ----------
  R.scenes.quote = {
    setup(node, { card, params }) {
      let text = params.text || card.quote || "";
      if (/^[a-z]/.test(text)) text = "…" + text; // quote starts mid-sentence
      const size = text.length < 60 ? 38 : text.length < 140 ? 30 : 24;
      node.innerHTML = `
        <div class="center" style="top:100px;height:610px;justify-content:center;gap:20px">
          <div class="mark serif" style="font-size:120px;line-height:.6;color:var(--accent);height:60px">“</div>
          <blockquote class="serif q" style="font-size:${size}px;line-height:1.3;font-style:italic">${R.words(text)}</blockquote>
          <div class="by" style="font-size:15px;color:var(--muted)">${R.esc(params.by || card.authors.join(", "))}, <i class="serif">${R.esc(card.sourceTitle)}</i></div>
        </div>`;
      return { mark: node.querySelector(".mark"), words: [...node.querySelectorAll(".q .word")], by: node.querySelector(".by") };
    },
    update(node, t, { duration }, s) {
      const p = R.back(R.clamp(R.seg(t, 0, 0.6)));
      s.mark.style.transform = `scale(${R.clamp(p, 0, 2)})`;
      const step = Math.min(0.22, (duration * 0.55) / Math.max(1, s.words.length));
      reveal(s.words, t, 0.4, step, 0.5, 10);
      fadeIn(s.by, t, 0.4 + s.words.length * step, 1.0 + s.words.length * step);
    },
  };

  // ---------- apply it ----------
  R.scenes.apply = {
    setup(node, { card, params }) {
      node.innerHTML = `
        <div style="position:absolute;left:36px;right:36px;top:100px;height:610px;display:flex;flex-direction:column;justify-content:center">
          <div class="box" style="background:var(--apply);border-left:6px solid var(--apply-border);border-radius:18px;padding:30px 28px;color:var(--apply-fg);box-shadow:0 18px 40px -24px rgba(45,68,33,.55)">
            <div style="display:flex;align-items:center;gap:14px">
              <svg width="44" height="44" viewBox="0 0 44 44"><circle cx="22" cy="22" r="19" fill="none" stroke="var(--apply-border)" stroke-width="3" class="ring" stroke-dasharray="120" stroke-dashoffset="120"/><path d="M13 23 l6 6 l12 -13" fill="none" stroke="var(--apply-fg)" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" class="tick" stroke-dasharray="30" stroke-dashoffset="30"/></svg>
              <div style="font-size:15px;font-weight:800;letter-spacing:.16em">APPLY IT</div>
            </div>
            <p class="serif txt" style="margin-top:18px;font-size:27px;line-height:1.35">${R.words(params.text || card.applyIt)}</p>
          </div>
        </div>`;
      return { box: node.querySelector(".box"), ring: node.querySelector(".ring"), tick: node.querySelector(".tick"), words: [...node.querySelectorAll(".txt .word")] };
    },
    update(node, t, { duration }, s) {
      const p = R.easeOut(R.seg(t, 0, 0.7));
      s.box.style.transform = `translateY(${(1 - p) * 40}px) scale(${0.96 + 0.04 * p})`;
      s.box.style.opacity = p;
      s.ring.setAttribute("stroke-dashoffset", (120 * (1 - R.easeOut(R.seg(t, 0.4, 1.2)))).toFixed(1));
      s.tick.setAttribute("stroke-dashoffset", (30 * (1 - R.easeOut(R.seg(t, 1.0, 1.5)))).toFixed(1));
      const step = Math.min(0.16, (duration * 0.6) / Math.max(1, s.words.length));
      reveal(s.words, t, 0.6, step, 0.45, 8);
    },
  };

  // ---------- end card: full credit, licence, health note ----------
  R.scenes.end = {
    setup(node, { card }) {
      node.innerHTML = `
        <div class="center" style="top:100px;height:610px;justify-content:center;gap:16px">
          <div class="serif logo" style="font-size:54px;font-weight:700;color:var(--accent);letter-spacing:.01em">Reborn</div>
          <div class="tag" style="font-size:16px;color:var(--muted)">Great ideas, one minute at a time</div>
          <div class="rule" style="height:2px;width:90px;background:var(--accent-soft);margin:6px 0"></div>
          <div class="credit" style="font-size:15px;line-height:1.5;max-width:440px">
            Idea from <i class="serif" style="font-size:17px">${R.esc(card.sourceTitle)}</i> by ${R.esc(card.authors.join(", "))}.<br>
            <span style="color:var(--muted)">${R.esc(card.credit)}</span><br>
            <span style="color:var(--muted)">Licence: ${R.esc(card.licenceName)}</span>
          </div>
          ${card.health ? `<div class="note" style="margin-top:6px;padding:10px 14px;border-radius:10px;background:var(--warn);border:1px solid var(--warn-border);color:var(--warn-fg);font-size:14px;font-weight:600;max-width:440px">${R.esc(card.disclaimer)}</div>` : ""}
          <div class="cta" style="margin-top:8px;font-size:15px;font-weight:700;color:var(--accent)">Read the full card in Reborn</div>
        </div>`;
      return { parts: [...node.querySelectorAll(".logo,.tag,.rule,.credit,.note,.cta")] };
    },
    update(node, t, ctx, s) { reveal(s.parts, t, 0.1, 0.22, 0.6, 14); },
  };

  // ---------- race: The Hare and the Tortoise (original drawing) ----------
  const HARE = `
    <g class="hare">
      <g class="speed" opacity="0" stroke="#b08d6e" stroke-width="3" stroke-linecap="round">
        <line x1="-70" y1="-50" x2="-110" y2="-50"/><line x1="-64" y1="-36" x2="-120" y2="-36"/><line x1="-70" y1="-22" x2="-100" y2="-22"/>
      </g>
      <g class="hb">
        <g class="legB"><rect x="-6" y="-4" width="12" height="30" rx="6" fill="#9c7a5c"/></g>
        <g class="legF"><rect x="-5" y="-4" width="10" height="28" rx="5" fill="#9c7a5c"/></g>
        <circle cx="-40" cy="-42" r="9" fill="#fbf7f1"/>
        <ellipse cx="0" cy="-40" rx="40" ry="21" fill="#b08d6e"/>
        <ellipse cx="6" cy="-33" rx="24" ry="10" fill="#dcc6af"/>
        <g class="head" transform="translate(36,-62)">
          <g class="ears">
            <ellipse cx="-6" cy="-28" rx="6.5" ry="23" fill="#b08d6e" transform="rotate(-18 -6 -6)"/>
            <ellipse cx="-6" cy="-28" rx="3" ry="16" fill="#e7b9a8" transform="rotate(-18 -6 -6)"/>
            <ellipse cx="5" cy="-29" rx="6.5" ry="23" fill="#a58263" transform="rotate(8 5 -6)"/>
          </g>
          <circle r="17" fill="#b08d6e"/>
          <circle class="eyeO" cx="8" cy="-4" r="2.8" fill="#2a211b"/>
          <path class="eyeC" d="M4 -3 q4 3 8 0" stroke="#2a211b" stroke-width="2" fill="none" opacity="0"/>
          <circle cx="16" cy="2" r="2.6" fill="#d98a7a"/>
        </g>
      </g>
      <g class="zz" opacity="0" font-family="Reborn Serif" font-weight="700" fill="#7a6a5d">
        <text class="z1" font-size="22">z</text><text class="z2" font-size="28">z</text><text class="z3" font-size="34">Z</text>
      </g>
    </g>`;
  const TORTOISE = `
    <g class="tort">
      <g class="tl"><rect x="-30" y="-14" width="13" height="16" rx="5" fill="#7f9c68"/><rect x="12" y="-14" width="13" height="16" rx="5" fill="#7f9c68"/></g>
      <g class="tr"><rect x="-16" y="-14" width="13" height="16" rx="5" fill="#8fab78"/><rect x="24" y="-14" width="13" height="16" rx="5" fill="#8fab78"/></g>
      <path d="M-44 -18 l-12 6 l10 2 z" fill="#8fab78"/>
      <g class="head" transform="translate(50,-26)"><rect x="-16" y="-6" width="20" height="13" rx="6" fill="#9bb57f"/><circle r="12" fill="#9bb57f"/><circle cx="5" cy="-3" r="2.4" fill="#2a211b"/><path d="M4 5 q4 2 8 -1" stroke="#4f6b40" stroke-width="1.6" fill="none"/></g>
      <rect x="-44" y="-22" width="88" height="10" rx="5" fill="#59784a"/>
      <path d="M-40 -18 Q-38 -66 0 -68 Q38 -66 40 -18 Z" fill="#6d8f5a" stroke="#4f6b40" stroke-width="2.5"/>
      <path d="M-14 -58 l14 -6 l14 6 l2 16 l-16 8 l-16 -8 z M-14 -58 l-14 14 M14 -58 l14 14 M-16 -42 l-20 14 M16 -42 l20 14 M0 -34 l0 16" fill="none" stroke="#4f6b40" stroke-width="2.2" stroke-linejoin="round"/>
    </g>`;

  R.scenes.race = {
    setup(node, { params }) {
      const X = (p) => 30 + p * 470;
      const tree = params.tree ?? 0.66;
      const rnd = R.rng(7);
      const confetti = Array.from({ length: 46 }, (_, i) => {
        const c = ["#8f3b1b", "#6d8f5a", "#d9b44a", "#c97a5a", "#5f7f9c"][i % 5];
        return `<rect class="cf" width="7" height="12" rx="2" fill="${c}" data-x="${(rnd() * 540).toFixed(1)}" data-s="${(rnd() * 0.8).toFixed(2)}" data-v="${(140 + rnd() * 160).toFixed(1)}" data-r="${(rnd() * 720 - 360).toFixed(0)}"/>`;
      }).join("");
      node.innerHTML = svgBand(`
        <defs><linearGradient id="sky${params.seed || 0}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbf3e6"/><stop offset="1" stop-color="#f3e3cc"/></linearGradient></defs>
        <rect x="0" y="0" width="540" height="600" fill="transparent"/>
        <circle cx="420" cy="140" r="46" fill="#f3d39a" opacity=".85"/>
        <g class="far"><path d="M-40 380 Q60 290 160 350 T360 330 T600 340 L600 600 L-40 600 Z" fill="#e6d6bf"/></g>
        <g class="near"><path d="M-40 420 Q100 360 230 405 T520 395 T640 410 L640 600 L-40 600 Z" fill="#d6c3a5"/></g>
        <rect x="0" y="440" width="540" height="160" fill="#c9b28f"/>
        <rect x="0" y="440" width="540" height="6" fill="#b79e78"/>
        <g opacity=".35" stroke="#9c845f" stroke-width="2">${Array.from({ length: 12 }, (_, i) => `<line x1="${i * 50 + 10}" y1="458" x2="${i * 50 + 34}" y2="458"/><line x1="${i * 50 + 30}" y1="512" x2="${i * 50 + 54}" y2="512"/>`).join("")}</g>
        <g fill="#b39a74">${Array.from({ length: 9 }, (_, i) => `<path d="M${i * 62 + 20},${560 + (i % 2) * 22} q4,-14 8,0 q4,-10 8,0 z"/>`).join("")}</g>
        <g transform="translate(${X(tree)},440)"><rect x="-7" y="-90" width="14" height="90" fill="#8a5a3b"/><circle cx="0" cy="-110" r="44" fill="#7f9c68"/><circle cx="-28" cy="-92" r="28" fill="#8fab78"/><circle cx="30" cy="-94" r="26" fill="#6d8f5a"/></g>
        <g transform="translate(${X(0.04)},440)"><rect x="-2" y="-4" width="4" height="62" fill="#fbf7f1"/><text x="0" y="80" text-anchor="middle" font-size="12" font-weight="700" fill="#7a6a5d">START</text></g>
        <g class="finish" transform="translate(${X(0.92)},440)">
          <rect x="-3" y="-120" width="6" height="182" fill="#5b4636"/><rect x="-2" y="0" width="4" height="62" fill="#fbf7f1"/>
          <g class="flag"><rect x="3" y="-120" width="44" height="28" fill="#fbf7f1"/>${[0, 1, 2, 3].map((c) => [0, 1].map((r) => (c + r) % 2 ? "" : `<rect x="${3 + c * 11}" y="${-120 + r * 14}" width="11" height="14" fill="#2a211b"/>`).join("")).join("")}</g>
          <text x="0" y="80" text-anchor="middle" font-size="12" font-weight="700" fill="#7a6a5d">FINISH</text>
        </g>
        <g class="tortWrap">${TORTOISE}</g>
        <g class="hareWrap">${HARE}</g>
        <text class="label" x="270" y="70" text-anchor="middle" font-family="Reborn Serif" font-size="32" font-weight="600" fill="#2a211b" opacity="0">${R.esc(params.label || "")}</text>
        <g class="confetti">${confetti}</g>
      `);
      const q = (s) => node.querySelector(s);
      return { X, q, hare: q(".hareWrap"), tort: q(".tortWrap"), label: q(".label"), confetti: [...node.querySelectorAll(".cf")],
        legF: q(".hare .legF"), legB: q(".hare .legB"), hb: q(".hare .hb"), ears: q(".hare .ears"), eyeO: q(".hare .eyeO"), eyeC: q(".hare .eyeC"),
        zz: q(".hare .zz"), z: [q(".z1"), q(".z2"), q(".z3")], speed: q(".hare .speed"),
        tl: q(".tort .tl"), tr: q(".tort .tr"), thead: q(".tort .head"), flag: q(".flag"), far: q(".far"), near: q(".near") };
    },
    update(node, t, { params, duration }, s) {
      const h = params.hare || { from: 0.05, to: 0.05, state: "idle" };
      const tt = params.tortoise || { from: 0.05, to: 0.05 };
      if (s.label.textContent) s.label.setAttribute("opacity", fadeIn({ style: {} }, t, 0.1, 0.6).toFixed(2));

      // Hare
      let hx = h.from, running = false, sleeping = false;
      if (h.state === "run") {
        const p = R.easeOut(R.seg(t, 0.3, Math.max(1.2, duration * 0.45)));
        hx = R.lerp(h.from, h.to, p); running = p < 0.995;
      } else if (h.state === "sleep") {
        sleeping = true;
      } else if (h.state === "wake") {
        const wake = (h.wakeAt ?? 0.6) * duration;
        if (t < wake) sleeping = true;
        else { const p = R.ease(R.seg(t, wake + 0.4, duration - 0.2)); hx = R.lerp(h.from, h.to, p); running = t > wake + 0.4 && p < 0.995; }
      }
      const cyc = t * 16;
      s.legF.setAttribute("transform", `translate(20,-24) rotate(${running ? Math.sin(cyc) * 50 : sleeping ? 80 : 0})`);
      s.legB.setAttribute("transform", `translate(-22,-26) rotate(${running ? -Math.sin(cyc) * 50 : sleeping ? 80 : 0})`);
      const bob = running ? -Math.abs(Math.sin(cyc)) * 10 : 0;
      s.hb.setAttribute("transform", sleeping ? "translate(0,16) rotate(4)" : `translate(0,${bob.toFixed(2)})`);
      s.ears.setAttribute("transform", sleeping ? "rotate(-70 0 -6)" : running ? "rotate(-25 0 -6)" : "rotate(0)");
      s.eyeO.setAttribute("opacity", sleeping ? 0 : 1);
      s.eyeC.setAttribute("opacity", sleeping ? 1 : 0);
      s.speed.setAttribute("opacity", running ? 0.7 : 0);
      s.zz.setAttribute("opacity", sleeping ? 1 : 0);
      s.z.forEach((z, i) => {
        const k = ((t * 0.6 + i / 3) % 1);
        z.setAttribute("x", (40 + i * 14 + k * 18).toFixed(1));
        z.setAttribute("y", (-70 - k * 70 - i * 6).toFixed(1));
        z.setAttribute("opacity", (Math.sin(k * Math.PI)).toFixed(2));
      });
      s.hare.setAttribute("transform", `translate(${s.X(hx).toFixed(1)},436)`);

      // Tortoise: perfectly steady pace, the point of the fable
      const tp = R.seg(t, 0.2, duration - 0.3);
      const tx = R.lerp(tt.from, tt.to, tp);
      const moving = tt.to !== tt.from && tp > 0 && tp < 1;
      const step = t * 5;
      s.tl.setAttribute("transform", `translate(${moving ? Math.sin(step) * 3 : 0},${moving ? Math.max(0, Math.sin(step)) * -3 : 0})`);
      s.tr.setAttribute("transform", `translate(${moving ? -Math.sin(step) * 3 : 0},${moving ? Math.max(0, -Math.sin(step)) * -3 : 0})`);
      s.thead.setAttribute("transform", `translate(${50 + (moving ? Math.sin(step) * 2 : 0)},-26)`);
      s.tort.setAttribute("transform", `translate(${s.X(tx).toFixed(1)},${(492 + (moving ? -Math.abs(Math.sin(step)) * 1.5 : 0)).toFixed(2)})`);

      s.flag.setAttribute("transform", `skewY(${Math.sin(t * 3) * 4})`);
      s.far.setAttribute("transform", `translate(${Math.sin(t * 0.2) * 6},0)`);

      // Confetti once the tortoise crosses the line
      let crossT = Infinity;
      if (params.cheer && tt.to > tt.from && tt.to >= 0.92) {
        const pc = (0.92 - tt.from) / (tt.to - tt.from);
        crossT = 0.2 + pc * (duration - 0.5);
      }
      s.confetti.forEach((c) => {
        const k = t - crossT - Number(c.dataset.s);
        if (k <= 0) { c.setAttribute("opacity", 0); return; }
        const y = -20 + k * Number(c.dataset.v);
        const x = Number(c.dataset.x) + Math.sin(k * 3 + Number(c.dataset.x)) * 16;
        c.setAttribute("opacity", y > 520 ? 0 : 1);
        c.setAttribute("transform", `translate(${x.toFixed(1)},${y.toFixed(1)}) rotate(${(k * Number(c.dataset.r)).toFixed(0)})`);
      });
    },
  };

  // ---------- compound: cumulative progress of two habits ----------
  R.scenes.compound = {
    setup(node, { params }) {
      const days = params.days || 14;
      const series = (params.series || []).map((sr) => {
        let acc = 0; const cum = [0, ...sr.values.slice(0, days).map((v) => (acc += v))];
        return { ...sr, cum };
      });
      const max = Math.max(...series.flatMap((sr) => sr.cum)) * 1.12 || 1;
      const L = 60, Rr = 470, T = 140, B = 520;
      const X = (d) => L + (d / days) * (Rr - L), Y = (v) => B - (v / max) * (B - T);
      node.innerHTML = svgBand(`
        <text x="270" y="70" text-anchor="middle" font-family="Reborn Serif" font-size="28" font-weight="600" fill="#2a211b">${R.esc(params.title || "Progress over two weeks")}</text>
        <line x1="${L}" y1="${B}" x2="${Rr}" y2="${B}" stroke="#bfae98" stroke-width="2"/>
        <line x1="${L}" y1="${T - 10}" x2="${L}" y2="${B}" stroke="#bfae98" stroke-width="2"/>
        <text x="${L}" y="${B + 26}" font-size="13" fill="#7a6a5d">Day 1</text>
        <text x="${Rr}" y="${B + 26}" font-size="13" fill="#7a6a5d" text-anchor="end">Day ${days}</text>
        <text x="${L - 12}" y="${T - 18}" font-size="13" fill="#7a6a5d">progress</text>
        ${series.map((sr, i) => `
          <g class="bars" data-i="${i}">${sr.values.slice(0, days).map((v, d) => `<rect class="bar" data-d="${d}" x="${(X(d) + 4 + i * 11).toFixed(1)}" width="10" y="${B}" height="0" rx="2" fill="${sr.color}" opacity=".35" data-h="${((v / max) * (B - T) * 2.2).toFixed(1)}"/>`).join("")}</g>
          <polyline class="ln" data-i="${i}" fill="none" stroke="${sr.color}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
          <circle class="dot" data-i="${i}" r="8" fill="${sr.color}" stroke="#fbf7f1" stroke-width="3"/>
          <text class="lab" data-i="${i}" font-size="15" font-weight="700" fill="${sr.color}"></text>`).join("")}
      `);
      return { series, days, X, Y, B, lns: [...node.querySelectorAll(".ln")], dots: [...node.querySelectorAll(".dot")],
        labs: [...node.querySelectorAll(".lab")], bars: [...node.querySelectorAll(".bars")].map((g) => [...g.querySelectorAll(".bar")]) };
    },
    update(node, t, { duration }, s) {
      const d = s.days * R.seg(t, 0.6, duration * 0.82);
      const labY = [];
      s.series.forEach((sr, i) => {
        const pts = [];
        for (let k = 0; k <= Math.floor(d); k++) pts.push([s.X(k), s.Y(sr.cum[k])]);
        const fl = Math.floor(d), fr = d - fl;
        let cur = [s.X(fl), s.Y(sr.cum[fl])];
        if (fl < s.days) { cur = [s.X(fl + fr), s.Y(R.lerp(sr.cum[fl], sr.cum[fl + 1], fr))]; pts.push(cur); }
        s.lns[i].setAttribute("points", pts.map((p) => p.map((v) => v.toFixed(1)).join(",")).join(" "));
        s.dots[i].setAttribute("cx", cur[0].toFixed(1)); s.dots[i].setAttribute("cy", cur[1].toFixed(1));
        s.labs[i].setAttribute("x", Math.min(cur[0] + 14, 330).toFixed(1));
        let ly = cur[1] - 14;
        for (const other of labY) if (Math.abs(other - ly) < 22) ly = other + (ly >= other ? 22 : -22);
        labY.push(ly);
        s.labs[i].setAttribute("y", ly.toFixed(1));
        s.labs[i].textContent = sr.label;
        s.bars[i].forEach((b, k) => {
          const p = R.easeOut(R.clamp(d - k));
          const hh = Number(b.dataset.h) * 0.25 * p;
          b.setAttribute("y", (s.B - hh).toFixed(1)); b.setAttribute("height", hh.toFixed(1));
        });
      });
    },
  };

  // ---------- hourglass: time leaking away, or aimed at what matters ----------
  R.scenes.hourglass = {
    setup(node, { params }) {
      const leak = (params.mode || "leak") === "leak";
      const labels = params.labels || [];
      const spots = leak ? [[92, 160], [448, 190], [88, 330], [452, 360]] : [[95, 565], [270, 565], [445, 565]];
      const glass = "M160,86 C160,190 262,250 262,293 C262,336 160,396 160,500 L380,500 C380,396 278,336 278,293 C278,250 380,190 380,86 Z";
      const rnd = R.rng(leak ? 11 : 13);
      const parts = leak ? Array.from({ length: 60 }, (_, i) => {
        const crack = i % 2; const target = (i % 4);
        return { crack, target, off: rnd() * 2.2, jx: rnd() * 30 - 15, jy: rnd() * 30 - 15 };
      }) : [];
      node.innerHTML = svgBand(`
        <defs>
          <clipPath id="g${leak ? "l" : "a"}"><path d="${glass}"/></clipPath>
          <radialGradient id="glow"><stop offset="0" stop-color="#f3c86b" stop-opacity=".7"/><stop offset="1" stop-color="#f3c86b" stop-opacity="0"/></radialGradient>
        </defs>
        ${leak ? "" : `<circle class="halo" cx="270" cy="420" r="170" fill="url(#glow)" opacity="0"/>`}
        <rect x="140" y="66" width="260" height="20" rx="6" fill="#8a5a3b"/>
        <rect x="140" y="500" width="260" height="20" rx="6" fill="#8a5a3b"/>
        <rect x="150" y="86" width="8" height="414" fill="#a97a55"/><rect x="382" y="86" width="8" height="414" fill="#a97a55"/>
        <g clip-path="url(#g${leak ? "l" : "a"})">
          <rect x="150" y="86" width="240" height="420" fill="#fbf7f1" opacity=".55"/>
          <rect class="top" x="150" y="120" width="240" height="180" fill="#d9a85a"/>
          <rect class="stream" x="268" y="293" width="4" height="207" fill="#d9a85a"/>
          <path class="pile" fill="#d9a85a"/>
        </g>
        <path d="${glass}" fill="none" stroke="#7a6a5d" stroke-width="3"/>
        <path d="M178,110 C182,170 220,215 240,240" fill="none" stroke="#fff" stroke-width="4" opacity=".6" stroke-linecap="round"/>
        ${leak ? `<g class="cracks" stroke="#2a211b" stroke-width="2" fill="none" stroke-linecap="round" opacity="0">
            <path d="M196,196 l-10,8 l6,6 l-12,10 M196,196 l8,12"/><path d="M346,206 l12,6 l-4,9 l14,8 M346,206 l-6,12"/></g>` : ""}
        <g class="parts">${parts.map(() => `<circle r="3" fill="#d9a85a"/>`).join("")}</g>
        ${leak ? "" : spots.map(([x, y], i) => `<path class="wire" d="M270,520 C270,540 ${x},530 ${x},${y - 22}" fill="none" stroke="#d9a85a" stroke-width="3" opacity="0"/>`).join("")}
        ${labels.slice(0, spots.length).map((l, i) => `
          <g class="pill" transform="translate(${spots[i][0]},${spots[i][1]})" opacity="0">
            <rect x="-70" y="-20" width="140" height="40" rx="20" fill="${leak ? "#efe4d6" : "#8f3b1b"}" stroke="${leak ? "#bfae98" : "#8f3b1b"}" stroke-width="2"/>
            <text text-anchor="middle" y="6" font-size="16" font-weight="700" fill="${leak ? "#7a6a5d" : "#fffaf3"}">${R.esc(l)}</text>
          </g>`).join("")}
      `);
      return { leak, spots, parts, partEls: [...node.querySelectorAll(".parts circle")], pills: [...node.querySelectorAll(".pill")],
        wires: [...node.querySelectorAll(".wire")], top: node.querySelector(".top"), stream: node.querySelector(".stream"),
        pile: node.querySelector(".pile"), cracks: node.querySelector(".cracks"), halo: node.querySelector(".halo") };
    },
    update(node, t, { duration }, s) {
      const p = R.seg(t, 0.3, duration - 0.4);
      const topY = R.lerp(130, 285, p);
      s.top.setAttribute("y", topY.toFixed(1)); s.top.setAttribute("height", (300 - topY).toFixed(1));
      const pileH = s.leak ? 6 + 34 * p : 6 + 150 * R.easeOut(p);
      const py = 500 - pileH;
      s.pile.setAttribute("d", `M150,500 L150,${(py + pileH * 0.55).toFixed(1)} Q270,${(py - pileH * 0.25).toFixed(1)} 390,${(py + pileH * 0.55).toFixed(1)} L390,500 Z`);
      s.stream.setAttribute("y", 293); s.stream.setAttribute("height", Math.max(0, py - 293 + 6).toFixed(1));
      s.stream.setAttribute("width", s.leak ? 2.5 : 5); s.stream.setAttribute("x", s.leak ? 268.75 : 267.5);

      if (s.leak) {
        s.cracks.setAttribute("opacity", R.seg(t, 0.6, 0.9).toFixed(2));
        const crackPts = [[192, 204], [350, 214]];
        s.partEls.forEach((c, i) => {
          const pr = s.parts[i];
          const spot = s.spots[pr.target % s.spots.length];
          const src = crackPts[spot[0] < 270 ? 0 : 1];
          const life = 1.8;
          const k = (t - 0.9 - pr.off);
          if (k < 0) { c.setAttribute("opacity", 0); return; }
          const ph = (k % life) / life;
          const x = R.lerp(src[0], spot[0] + pr.jx, R.easeOut(ph));
          const y = R.lerp(src[1], spot[1] + pr.jy, ph) + Math.sin(ph * Math.PI) * -30;
          c.setAttribute("cx", x.toFixed(1)); c.setAttribute("cy", y.toFixed(1));
          c.setAttribute("opacity", (Math.sin(ph * Math.PI) * 0.9).toFixed(2));
        });
        s.pills.forEach((g, i) => {
          const a = R.easeOut(R.seg(t, 1.6 + i * 0.6, 2.2 + i * 0.6));
          const drift = Math.min(14, Math.max(0, t - (2.2 + i * 0.6)) * 3);
          g.setAttribute("opacity", (a * (1 - R.seg(t, duration - 1.2, duration) * 0.6)).toFixed(2));
          const [x, y] = s.spots[i];
          g.setAttribute("transform", `translate(${(x + (x < 270 ? -drift : drift)).toFixed(1)},${(y - drift * 0.6).toFixed(1)}) rotate(${(x < 270 ? -1 : 1) * Math.min(6, drift)})`);
        });
      } else {
        s.halo.setAttribute("opacity", (0.4 + 0.3 * Math.sin(t * 2)) * R.seg(t, 0.5, 1.5));
        s.wires.forEach((w, i) => w.setAttribute("opacity", R.seg(t, 1.2 + i * 0.7, 1.7 + i * 0.7).toFixed(2)));
        s.pills.forEach((g, i) => {
          const a = R.back(R.seg(t, 1.4 + i * 0.7, 2.0 + i * 0.7));
          const [x, y] = s.spots[i];
          g.setAttribute("opacity", R.clamp(a).toFixed(2));
          g.setAttribute("transform", `translate(${x},${y}) scale(${R.clamp(a, 0, 1.2).toFixed(3)})`);
        });
      }
    },
  };



  // ---------- shape: the background forms an object (swarm, depth); a headline sits under it ----------
  R.scenes.shape = {
    setup(node, { card, params }) {
      const headline = params.headline === "title" ? card.title : params.headline || "";
      const sub = params.sub === "source" ? `From <i class="serif">${R.esc(card.sourceTitle)}</i> · ${R.esc(card.authors.join(", "))}` : R.esc(params.sub || "");
      node.innerHTML = `
        <div class="center" style="top:${params.top ?? 560}px;gap:10px">
          ${params.eyebrow ? `<div class="eyebrow">${R.esc(params.eyebrow)}</div>` : ""}
          ${headline ? `<div class="serif hl" style="font-size:${params.size || (headline.length > 50 ? 26 : 32)}px;line-height:1.18;font-weight:700">${R.words(headline)}</div>` : ""}
          ${sub ? `<div class="sub" style="font-size:15px;color:var(--muted)">${sub}</div>` : ""}
        </div>`;
      return { eyebrow: node.querySelector(".eyebrow"), words: [...node.querySelectorAll(".hl .word")], sub: node.querySelector(".sub") };
    },
    update(node, t, { params }, s) {
      const at = params.at ?? 1.2; // let the shape form first
      if (s.eyebrow) fadeIn(s.eyebrow, t, at - 0.4, at + 0.2);
      reveal(s.words, t, at, 0.06, 0.5, 12);
      if (s.sub) fadeIn(s.sub, t, at + 0.4 + s.words.length * 0.06, at + 1.0 + s.words.length * 0.06);
    },
  };

  // ---------- core: abstract energy core that leaks sparks (or channels them into beams) ----------
  R.scenes.core = {
    setup(node, { params }) {
      const leak = (params.mode || "leak") === "leak";
      const labels = params.labels || [];
      const rnd = R.rng(leak ? 41 : 43);
      const N = 120;
      const parts = Array.from({ length: N }, () => ({ a: rnd() * Math.PI * 2, v: 90 + rnd() * 170, r: 1 + rnd() * 2.6, off: rnd() }));
      const angles = leak ? labels.map((_, i) => -Math.PI / 2 + (i + 0.5) * (Math.PI * 2 / labels.length) + 0.35) : labels.map((_, i) => Math.PI / 2 + (i - (labels.length - 1) / 2) * 0.75);
      node.innerHTML = svgBand(`
        <defs>
          <filter id="cg${leak ? "l" : "a"}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="7" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
          <radialGradient id="cc${leak ? "l" : "a"}"><stop offset="0" stop-color="#fff"/><stop offset=".35" stop-color="var(--accent)"/><stop offset="1" stop-color="var(--accent)" stop-opacity="0"/></radialGradient>
        </defs>
        <g filter="url(#cg${leak ? "l" : "a"})">
          <circle class="halo" cx="270" cy="290" r="150" fill="url(#cc${leak ? "l" : "a"})" opacity=".35"/>
          <circle class="ring" cx="270" cy="290" r="96" fill="none" stroke="var(--accent)" stroke-width="2" stroke-dasharray="6 10"/>
          <circle class="ring2" cx="270" cy="290" r="122" fill="none" stroke="var(--accent)" stroke-width="1" stroke-dasharray="2 14" opacity=".6"/>
          <circle class="orb" cx="270" cy="290" r="64" fill="url(#cc${leak ? "l" : "a"})"/>
          <g class="beams">${leak ? "" : angles.map(() => `<path fill="none" stroke="var(--accent)" stroke-width="3" stroke-linecap="round"/>`).join("")}</g>
          <g class="parts">${parts.map((p) => `<circle r="${p.r.toFixed(1)}" fill="var(--accent)"/>`).join("")}</g>
        </g>
        ${labels.map((l) => `<text class="lbl" text-anchor="middle" font-size="19" font-weight="700" letter-spacing="1.5" fill="var(--ink)" style="text-transform:uppercase;text-shadow:0 0 14px var(--glow)" opacity="0">${R.esc(l)}</text>`).join("")}
      `);
      node.querySelector("svg").classList.add("raw"); // drawn in light already; skip the line-art treatment
      return { leak, parts, angles, el: (q) => node.querySelector(q), partEls: [...node.querySelectorAll(".parts circle")],
        beams: [...node.querySelectorAll(".beams path")], lbls: [...node.querySelectorAll(".lbl")] };
    },
    update(node, t, { duration }, s) {
      const p = R.seg(t, 0.3, duration - 0.3);
      const pulse = 1 + 0.05 * Math.sin(t * 5);
      const orbR = s.leak ? R.lerp(70, 34, R.easeOut(p)) : R.lerp(40, 78, R.easeOut(p));
      s.el(".orb").setAttribute("r", (orbR * pulse).toFixed(1));
      s.el(".halo").setAttribute("r", (orbR * 2.4).toFixed(1));
      s.el(".ring").setAttribute("transform", `rotate(${(t * 22).toFixed(1)} 270 290)`);
      s.el(".ring2").setAttribute("transform", `rotate(${(-t * 14).toFixed(1)} 270 290)`);
      const L = 1.6;
      const on = R.seg(t, 0.4, 1.0);
      s.partEls.forEach((c, i) => {
        const pr = s.parts[i];
        const k = t / L + pr.off;
        const age = (k % 1);
        const cycle = Math.floor(k);
        let x, y, a;
        if (s.leak) {
          const ang = pr.a + Math.sin(cycle * 12.9898 + i) * 0.5; // a new heading every life
          const r = orbR * 0.8 + age * pr.v * L;
          x = 270 + Math.cos(ang) * r; y = 290 + Math.sin(ang) * r;
          a = (1 - age) * on;
        } else {
          // Sparks are drawn in from outside and fly out along the beams.
          const j = i % Math.max(1, s.angles.length);
          const ang = s.angles[j] + Math.sin(i * 7.1) * 0.06;
          const r = orbR * 0.9 + age * 260;
          x = 270 + Math.cos(ang) * r; y = 290 + Math.sin(ang) * r;
          a = Math.sin(age * Math.PI) * R.seg(t, 1.2 + j * 0.6, 1.8 + j * 0.6);
        }
        c.setAttribute("cx", x.toFixed(1)); c.setAttribute("cy", y.toFixed(1)); c.setAttribute("opacity", a.toFixed(2));
      });
      s.beams.forEach((b, j) => {
        const g = R.easeOut(R.seg(t, 1.0 + j * 0.6, 1.7 + j * 0.6));
        const ang = s.angles[j];
        const r1 = orbR + 4, r2 = orbR + 4 + g * 200;
        b.setAttribute("d", `M${(270 + Math.cos(ang) * r1).toFixed(1)},${(290 + Math.sin(ang) * r1).toFixed(1)} L${(270 + Math.cos(ang) * r2).toFixed(1)},${(290 + Math.sin(ang) * r2).toFixed(1)}`);
        b.setAttribute("opacity", (g * (0.7 + 0.3 * Math.sin(t * 9 + j))).toFixed(2));
      });
      s.lbls.forEach((l, j) => {
        const start = (s.leak ? 1.4 : 1.4) + j * 0.6;
        const a = R.easeOut(R.seg(t, start, start + 0.6));
        const drift = s.leak ? Math.max(0, t - start) * 9 : 0;
        const r = (s.leak ? 175 : 238) + drift;
        const ang = s.angles[j];
        l.setAttribute("x", (270 + Math.cos(ang) * r).toFixed(1));
        l.setAttribute("y", (296 + Math.sin(ang) * r).toFixed(1));
        l.setAttribute("opacity", (a * (s.leak ? 1 - 0.55 * R.seg(t, start + 1.5, duration) : 1)).toFixed(2));
      });
    },
  };

  // ---------- hours: a day of waking hours, most leaking away ----------
  R.scenes.hours = {
    setup(node, { params }) {
      const n = params.total || 16, cols = 4;
      const kept = new Map(Object.entries(params.kept || {}).map(([k, v]) => [Number(k), v]));
      const W = 104, H = 74, G = 12, left = (540 - (cols * W + (cols - 1) * G)) / 2, top = 200;
      const first = params.firstHour ?? 7;
      const label = (h) => { const hh = (first + h) % 24; return `${hh % 12 || 12}${hh < 12 ? "am" : "pm"}`; };
      node.innerHTML = `
        <div class="ttl serif" style="position:absolute;left:0;right:0;top:118px;text-align:center;font-size:30px;font-weight:600">${R.esc(params.title || "Your waking hours")}</div>
        ${Array.from({ length: n }, (_, i) => {
          const x = left + (i % cols) * (W + G), y = top + Math.floor(i / cols) * (H + G);
          const k = kept.has(i);
          return `<div class="blk" data-k="${k ? 1 : 0}" style="position:absolute;left:${x}px;top:${y}px;width:${W}px;height:${H}px;border-radius:14px;background:#fbf7f1;border:2px solid #d8c8b4;display:flex;flex-direction:column;justify-content:center;align-items:center;gap:2px">
            <div style="font-size:13px;font-weight:700;color:var(--muted)">${label(i)}</div>
            <div class="kl" style="font-size:14px;font-weight:700;color:#fffaf3;opacity:0">${R.esc(kept.get(i) || "")}</div></div>`;
        }).join("")}
        <div class="sum" style="position:absolute;left:0;right:0;top:${top + 4 * (H + G) + 8}px;text-align:center;font-size:20px;font-weight:700;color:var(--accent);opacity:0">${R.esc(params.summary || "")}</div>`;
      return { blks: [...node.querySelectorAll(".blk")], ttl: node.querySelector(".ttl"), sum: node.querySelector(".sum"), rnd: R.rng(5) };
    },
    update(node, t, { duration }, s) {
      fadeIn(s.ttl, t, 0, 0.5);
      const split = Math.min(3.2, duration * 0.35);
      const rnd = R.rng(5);
      s.blks.forEach((b, i) => {
        const a = R.easeOut(R.seg(t, 0.2 + i * 0.06, 0.6 + i * 0.06));
        const kept = b.dataset.k === "1";
        const wob = rnd() * 2 - 1, delay = rnd() * 1.4;
        if (kept) {
          const g = R.easeOut(R.seg(t, split, split + 0.6));
          b.style.background = g > 0 ? `rgba(143,59,27,${g.toFixed(2)})` : "#fbf7f1";
          b.style.borderColor = g > 0.5 ? "#8f3b1b" : "#d8c8b4";
          b.style.color = g > 0.5 ? "#fffaf3" : "";
          b.firstElementChild.style.color = g > 0.5 ? "#f6dccb" : "";
          b.querySelector(".kl").style.opacity = g.toFixed(2);
          b.style.transform = `translateY(${((1 - a) * 18).toFixed(1)}px) scale(${1 + 0.06 * g})`;
          b.style.boxShadow = g > 0 ? `0 10px 30px -12px rgba(143,59,27,${(0.7 * g).toFixed(2)})` : "none";
          b.style.opacity = a.toFixed(2);
        } else {
          const f = R.easeIn(R.seg(t, split + 0.3 + delay, split + 2.2 + delay));
          b.style.opacity = (a * (1 - f * 0.85)).toFixed(2);
          b.style.background = f > 0 ? "#efe4d6" : "#fbf7f1";
          b.style.transform = `translate(${(wob * 30 * f).toFixed(1)}px, ${((1 - a) * 18 + f * 150).toFixed(1)}px) rotate(${(wob * 25 * f).toFixed(1)}deg) scale(${1 - 0.25 * f})`;
        }
      });
      fadeIn(s.sum, t, split + 2.0, split + 2.6);
    },
  };

  // ---------- sort: what is up to you, and what is not ----------
  R.scenes.sort = {
    setup(node, { params }) {
      const items = params.items || [];
      const C = { in: { x: 140, y: 430 }, out: { x: 400, y: 430 } };
      const slots = { in: 0, out: 0 };
      const per = { in: items.filter((i) => i.side === "in").length, out: items.filter((i) => i.side !== "in").length };
      node.innerHTML = `
        ${["in", "out"].map((k) => `<div class="circ ${k}" style="position:absolute;left:${C[k].x - 128}px;top:${C[k].y - 128}px;width:256px;height:256px;border-radius:50%;
            background:${k === "in" ? "rgba(143,59,27,.10)" : "rgba(95,127,156,.10)"};border:3px solid ${k === "in" ? "#8f3b1b" : "#5f7f9c"}"></div>
          <div class="cap ${k}" style="position:absolute;left:${C[k].x - 120}px;width:240px;top:${C[k].y - 172}px;text-align:center;font-size:20px;font-weight:800;color:${k === "in" ? "#8f3b1b" : "#5f7f9c"}">${k === "in" ? R.esc(params.inLabel || "Up to you") : R.esc(params.outLabel || "Not up to you")}</div>`).join("")}
        ${items.map((it, i) => {
          const side = it.side === "in" ? "in" : "out";
          const k = slots[side]++;
          const y = C[side].y + (k - (per[side] - 1) / 2) * 46;
          return `<div class="item" data-side="${side}" data-tx="${C[side].x}" data-ty="${y}" style="position:absolute;left:0;top:0;transform-origin:0 0">
            <div style="transform:translate(-50%,-50%);white-space:nowrap;padding:7px 13px;border-radius:999px;font-size:14px;font-weight:700;background:#fbf7f1;border:2px solid ${side === "in" ? "#8f3b1b" : "#5f7f9c"};color:${side === "in" ? "#6d2a12" : "#3f5a72"}">${R.esc(it.text)}</div></div>`;
        }).join("")}
        <div class="note serif" style="position:absolute;left:30px;right:30px;top:150px;text-align:center;font-size:24px;font-weight:600;opacity:0">${R.esc(params.note || "")}</div>`;
      return { items: [...node.querySelectorAll(".item")], circ: { in: node.querySelector(".circ.in"), out: node.querySelector(".circ.out") },
        cap: { in: node.querySelector(".cap.in"), out: node.querySelector(".cap.out") }, note: node.querySelector(".note") };
    },
    update(node, t, { params, duration }, s) {
      const focus = params.mode === "focus";
      for (const k of ["in", "out"]) {
        const a = focus ? 1 : R.easeOut(R.seg(t, 0.1, 0.7));
        let sc = 0.85 + 0.15 * a;
        let op = a;
        if (focus) {
          const f = R.ease(R.seg(t, 0.4, 1.6));
          sc = k === "in" ? 1 + 0.07 * f : 1 - 0.1 * f;
          op = k === "in" ? 1 : 1 - 0.45 * f;
          if (k === "in") s.circ.in.style.boxShadow = `0 0 ${(50 * f).toFixed(0)}px ${(10 * f).toFixed(0)}px rgba(143,59,27,${(0.25 * f).toFixed(2)})`;
        }
        s.circ[k].style.transform = `scale(${sc.toFixed(3)})`; s.circ[k].style.opacity = op.toFixed(2);
        s.cap[k].style.opacity = op.toFixed(2);
      }
      const n = s.items.length;
      const span = Math.max(1, duration - 1.6);
      s.items.forEach((it, i) => {
        const tx = Number(it.dataset.tx), ty = Number(it.dataset.ty);
        const side = it.dataset.side;
        if (focus) {
          const f = R.ease(R.seg(t, 0.4, 1.6));
          const c = side === "in" ? 140 : 400;
          const sc = side === "in" ? 1 + 0.07 * f : 1 - 0.1 * f;
          const dx = side === "out" ? Math.sin(t * 1.3 + i) * 10 * f : 0;
          const dy = side === "out" ? Math.cos(t * 1.1 + i * 2) * 6 * f : 0;
          it.style.transform = `translate(${(c + (tx - c) * sc + dx).toFixed(1)}px,${(430 + (ty - 430) * sc + dy).toFixed(1)}px)`;
          it.style.opacity = side === "out" ? (1 - 0.5 * f).toFixed(2) : "1";
          return;
        }
        const st = 0.7 + (i / n) * span * 0.85;
        const appear = R.easeOut(R.seg(t, st, st + 0.35));
        const fly = R.ease(R.seg(t, st + 0.5, st + 1.1));
        const x = R.lerp(270, tx, fly), y = R.lerp(170, ty, fly) - Math.sin(fly * Math.PI) * 40;
        it.style.opacity = appear.toFixed(2);
        it.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) scale(${(0.8 + 0.2 * appear).toFixed(3)})`;
      });
      if (s.note.textContent) fadeIn(s.note, t, focus ? 1.2 : duration - 1.5, focus ? 1.8 : duration - 0.9);
    },
  };

  // ---------- breathe: in for N, out for N ----------
  R.scenes.breathe = {
    setup(node, { params }) {
      node.innerHTML = `
        <div class="ttl" style="position:absolute;left:0;right:0;top:122px;text-align:center;font-size:22px;font-weight:700;color:var(--muted)"></div>
        ${[0, 1, 2].map((i) => `<div class="ring" style="position:absolute;left:270px;top:420px;width:0;height:0;border-radius:50%;border:2px solid rgba(109,143,90,.5)"></div>`).join("")}
        <div class="orb" style="position:absolute;left:270px;top:420px;border-radius:50%;background:radial-gradient(circle at 40% 35%, #cfe1c2, #8fab78 65%, #6d8f5a);box-shadow:0 20px 60px -20px rgba(77,107,64,.7)"></div>
        <div class="txt" style="position:absolute;left:0;right:0;top:376px;text-align:center;color:#fffaf3">
          <div class="word1" style="font-size:22px;font-weight:700;letter-spacing:.12em;text-transform:uppercase"></div>
          <div class="num serif" style="font-size:64px;font-weight:700;line-height:1"></div>
        </div>
        <div class="cyc" style="position:absolute;left:0;right:0;top:640px;text-align:center;font-size:15px;font-weight:600;color:var(--muted)"></div>`;
      return { ttl: node.querySelector(".ttl"), orb: node.querySelector(".orb"), rings: [...node.querySelectorAll(".ring")],
        w: node.querySelector(".word1"), num: node.querySelector(".num"), cyc: node.querySelector(".cyc") };
    },
    update(node, t, { params }, s) {
      const inS = params.in || 5, outS = params.out || 5, lead = params.lead ?? 1.2, cycles = params.cycles || 2;
      const tt = t - lead, len = inS + outS;
      let r = 80, word = "Ready", num = "", title = params.title || "Slow belly breathing";
      if (tt >= 0 && tt < len * cycles) {
        const k = tt % len, c = Math.floor(tt / len);
        if (k < inS) { r = R.lerp(80, 175, R.ease(k / inS)); word = "In"; num = String(Math.floor(k) + 1); title = params.inText || "Breathe in through your nose"; }
        else { r = R.lerp(175, 80, R.ease((k - inS) / outS)); word = "Out"; num = String(Math.floor(k - inS) + 1); title = params.outText || "Breathe out through your mouth"; }
        s.cyc.textContent = `Breath ${c + 1} of ${cycles}`;
      } else if (tt >= len * cycles) { word = "Keep going"; s.cyc.textContent = params.after || "Try it for five minutes"; }
      else s.cyc.textContent = "";
      s.orb.style.width = s.orb.style.height = `${(r * 2).toFixed(1)}px`;
      s.orb.style.transform = `translate(-50%,-50%)`;
      s.rings.forEach((ring, i) => {
        const k = ((t * 0.35 + i / 3) % 1);
        const rr = r + k * 90;
        ring.style.width = ring.style.height = `${(rr * 2).toFixed(1)}px`;
        ring.style.transform = "translate(-50%,-50%)";
        ring.style.opacity = ((1 - k) * 0.8).toFixed(2);
      });
      s.ttl.textContent = title;
      s.w.textContent = word; s.num.textContent = num;
      s.w.style.fontSize = word.length > 4 ? "18px" : "22px";
    },
  };

  // ---------- grid: Franklin's virtue chart ----------
  R.scenes.grid = {
    setup(node, { params }) {
      const rows = params.rows || [];
      const days = ["S", "M", "T", "W", "T", "F", "S"];
      const LW = 128, CW = 46, RH = 31, left = (540 - (LW + 7 * CW)) / 2, top = 200;
      node.innerHTML = `
        <div class="ttl serif" style="position:absolute;left:0;right:0;top:120px;text-align:center;font-size:28px;font-weight:600"></div>
        <div class="tbl" style="position:absolute;left:${left}px;top:${top}px;width:${LW + 7 * CW}px">
          <div class="band" style="position:absolute;left:-8px;right:-8px;height:${RH}px;top:${RH}px;border-radius:8px;background:var(--accent-soft);opacity:0"></div>
          <div class="col" style="position:absolute;top:0;width:${CW}px;height:${RH * (rows.length + 1)}px;left:${LW}px;border-radius:8px;background:rgba(109,143,90,.14);opacity:0"></div>
          <div style="position:relative;display:flex;height:${RH}px;align-items:center;font-size:13px;font-weight:700;color:var(--muted)"><div style="width:${LW}px"></div>${days.map((d) => `<div style="width:${CW}px;text-align:center">${d}</div>`).join("")}</div>
          ${rows.map((r, i) => `<div class="row" style="position:relative;display:flex;height:${RH}px;align-items:center;border-top:1px solid #d8c8b4">
              <div class="rl" style="width:${LW}px;font-size:14px;font-weight:600">${R.esc(r)}</div>
              ${days.map((_, d) => `<div style="width:${CW}px;height:${RH}px;border-left:1px solid #e3d5c2;display:flex;align-items:center;justify-content:center"><div class="dot" data-r="${i}" data-d="${d}" style="width:11px;height:11px;border-radius:50%;background:#2a211b;opacity:0"></div></div>`).join("")}
            </div>`).join("")}
        </div>`;
      const dots = [...node.querySelectorAll(".dot")];
      return { ttl: node.querySelector(".ttl"), band: node.querySelector(".band"), col: node.querySelector(".col"), dots,
        rls: [...node.querySelectorAll(".rl")], tbl: node.querySelector(".tbl"), RH, CW, LW };
    },
    update(node, t, { params, duration }, s) {
      const rows = (params.rows || []).length;
      s.tbl.style.opacity = R.easeOut(R.seg(t, 0, 0.6)).toFixed(2);
      if (params.mode === "scatter") {
        s.ttl.textContent = params.title || "All thirteen at once";
        const rnd = R.rng(3);
        s.dots.forEach((d) => {
          const on = rnd() < (params.density ?? 0.45);
          const at = 0.8 + rnd() * (duration - 2);
          d.style.opacity = on && t > at ? "1" : "0";
          d.style.transform = `scale(${on ? R.back(R.seg(t, at, at + 0.3)).toFixed(2) : 0})`;
        });
        return;
      }
      // focus: one virtue per week, its row stays clean
      const weeks = params.weeks || 2;
      const lead = 0.6, wlen = (duration - lead - 0.4) / weeks;
      const w = R.clamp(Math.floor((t - lead) / wlen), 0, weeks - 1);
      const wt = t - lead - w * wlen;
      const day = R.clamp(Math.floor((wt / wlen) * 7), 0, 6);
      s.ttl.textContent = `Week ${w + 1}: ${(params.rows || [])[w] || ""}`;
      s.band.style.opacity = R.seg(t, lead, lead + 0.4).toFixed(2);
      s.band.style.transform = `translateY(${(w * s.RH).toFixed(1)}px)`;
      s.col.style.opacity = t > lead ? "1" : "0";
      s.col.style.transform = `translateX(${(day * s.CW).toFixed(1)}px)`;
      s.rls.forEach((rl, i) => { rl.style.color = i === w ? "var(--accent)" : ""; rl.style.fontWeight = i === w ? "800" : "600"; });
      const rnd = R.rng(17 + w);
      s.dots.forEach((d) => {
        const r = Number(d.dataset.r), dd = Number(d.dataset.d);
        const slip = rnd() < (params.density ?? 0.22) && r !== w;
        const show = slip && dd <= day && t > lead && rows;
        d.style.opacity = show ? "1" : "0";
        d.style.transform = `scale(${show ? 1 : 0})`;
      });
    },
  };
})();

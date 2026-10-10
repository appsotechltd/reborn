/* Reborn explainer runtime.
 *
 * The page is a pure function of time: the renderer calls window.__setup(timeline)
 * once, then window.__seek(t) for every frame and screenshots the stage. Nothing
 * here may depend on wall-clock time, timers or randomness without a seed, so a
 * render is identical every time.
 */
(function () {
  const FADE = 0.45; // crossfade between scenes, seconds

  let timeline = null;
  let mounted = [];

  function el(id) { return document.getElementById(id); }

  window.__setup = async function (tl) {
    timeline = tl;
    const card = tl.card;
    if (tl.theme) document.body.dataset.theme = tl.theme; else delete document.body.dataset.theme;
    if (tl.captionStyle) document.body.dataset.captions = tl.captionStyle; else delete document.body.dataset.captions;
    R.bg.setup(el("bgcanvas"), tl.theme, [...tl.scenes.slice(1).map((s) => s.start), ...tl.scenes.flatMap((s) => (s.beats || []).map((b) => b.start))], tl.scale || 2, tl);
    el("topic").textContent = card.topicName;
    el("health").hidden = !card.health;
    el("footer").innerHTML =
      `From <b>${R.esc(card.sourceTitle)}</b> · ${R.esc(card.authors.join(", "))}<br>${R.esc(card.licenceName)}`;

    const host = el("scenes");
    host.innerHTML = "";
    mounted = tl.scenes.map((s, i) => {
      const impl = R.scenes[s.type];
      if (!impl) throw new Error(`unknown scene type "${s.type}" (scene ${i})`);
      const node = document.createElement("div");
      node.className = "scene";
      node.style.opacity = "0";
      host.appendChild(node);
      const ctx = { card, params: s.params || {}, duration: s.duration, index: i };
      const state = impl.setup(node, ctx) || {};
      return { s, node, impl, ctx, state };
    });
    await document.fonts.ready;
    window.__seek(0);
    return true;
  };

  window.__seek = function (t) {
    if (!timeline) return;
    R.bg.draw(t);
    for (const m of mounted) {
      const local = t - m.s.start;
      const d = m.s.duration;
      // A scene marked "cut" continues the previous one exactly, so it switches without a crossfade.
      const next = mounted[m.ctx.index + 1];
      const first = m.ctx.index === 0 || m.s.cut;
      const last = !next || next.s.cut;
      let a = 1;
      if (!first) a = Math.min(a, R.clamp((local + FADE) / FADE)); // fade in during the previous scene's tail
      if (!last) a = Math.min(a, R.clamp((d - local) / FADE));
      if (local < (first ? 0 : -FADE) || local >= d + (last ? 0 : FADE)) a = 0;
      m.node.style.opacity = a.toFixed(3);
      m.node.style.visibility = a > 0 ? "visible" : "hidden";
      if (a > 0) m.impl.update(m.node, R.clamp(local, 0, d), m.ctx, m.state);
    }

    // Burned-in captions: the phrase being spoken right now.
    let cur = null;
    for (const s of timeline.scenes) {
      for (const c of s.captions) {
        if (t >= c.start && t < c.end) cur = c;
      }
    }
    const cap = el("caption");
    const text = cur ? cur.text : "";
    if (timeline.captionStyle === "cinema") {
      // Word by word: each word lights up as it is spoken.
      if (cap.dataset.text !== text) { cap.dataset.text = text; cap.innerHTML = R.words(text, "cw"); }
      if (cur) {
        const ws = cap.querySelectorAll(".cw");
        const p = (t - cur.start) / (cur.end - cur.start);
        ws.forEach((w, i) => w.classList.toggle("on", i <= Math.floor(p * ws.length)));
      }
    } else if (cap.textContent !== text) cap.textContent = text;

    el("progress").style.width = `${(R.clamp(t / timeline.duration) * 100).toFixed(2)}%`;
  };
})();

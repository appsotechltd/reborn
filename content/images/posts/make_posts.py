"""Make image posts: one designed 4:5 picture per card, shown in the feed instead of the text preview.

    python make_posts.py --all --free-only      # every card whose art costs nothing
    python make_posts.py --per-topic 1 --pay --max-new 33   # one card per category, at most 33 paid pictures
    python make_posts.py --cards aesops-fables--01 why-we-sleep-walker--01

Each post is a painted scene with the card's title, category, book and author set over it in
Fraunces, in the Candlelight colours. The words are set here, never by the image model, so they are
always spelled right.

Where the art comes from, cheapest first:
  1. The card's existing picture (images/cards/v1-full, illustrations and 3D only): free.
  2. Art picked by hand (art/<card-id>.png) or already made for this card and prompt, kept forever in the media store under
     images/posts/art/: free.
  3. Only with --pay: Ideogram 3.0 Turbo (IDEOGRAM_API_KEY), about $0.03 a picture. A short scene is written for each
     card first (OpenAI, OPENAI_API_KEY, fractions of a cent) and kept in scenes.json, and each new
     picture is checked for stray lettering and made once more if it has any.

Output goes to --out (default .cache/posts): art/ and posts/v1/<card-id>.jpg. Upload with
    reborn media-upload <out> images/posts
then commit posts.json and scenes.json; the API reads posts.json from CARD_IMAGE_DIR (../posts.json).
"""
import argparse
import base64
import concurrent.futures as cf
import hashlib
import io
import json
import os
import random
import re
import subprocess
import sys
import threading
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
LIBRARY = REPO / "content" / "library"
CARD_IMAGES = HERE.parent / "manifest.json"
POSTS = HERE.parent / "posts.json"
SCENES = HERE / "scenes.json"
FONTS = REPO / "app" / "assets" / "fonts"
TYPES_GO = REPO / "backend" / "internal" / "content" / "types.go"
MEDIA = os.environ.get("MEDIA_BASE_URL", "").rstrip("/")
CHAT_MODEL = os.environ.get("OPENAI_CHAT_MODEL", "gpt-5.4-mini")

W, H = 1080, 1350
CREAM, AMBER, INK = (244, 234, 216), (232, 163, 61), (12, 10, 8)
REUSE_TYPES = {"illustration", "3d"}  # charts carry their own labels, so they get new art

STYLE = ("Vertical 4:5 full-bleed painterly illustration, edge to edge, no border. Candlelight palette: deep warm "
         "near-black brown, glowing candle-amber and gold highlights. Cinematic warm light, fine grain. The subject sits "
         "in the lower half; the upper 45% of the picture is calm, dark, softly lit empty background with no objects. "
         "Absolutely no text, no letters, no words, no numbers, no signature.")
NEGATIVE = "text, letters, words, numbers, typography, captions, signature, logo, watermark, border, frame, white margin"

lock = threading.Lock()
spent = {"ideogram": 0, "reused": 0, "kept": 0, "retries": 0}


def topics():
    """Category id -> display name, from the API's list."""
    return dict(re.findall(r'\{"([a-z0-9-]+)", "([^"]+)"\}', TYPES_GO.read_text()))


def library():
    cards, sources = {}, {}
    for f in sorted(LIBRARY.glob("*.json")):
        d = json.loads(f.read_text())
        sources[d["source"]["id"]] = d["source"]
        for c in d["cards"]:
            cards[c["id"]] = c | {"source_id": d["source"]["id"]}
    return cards, sources


def load(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def http(url, data=None, headers=None, timeout=180):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": "Mozilla/5.0", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch(url):
    """A file's bytes, or None when it isn't there."""
    try:
        return http(url, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (403, 404):
            return None
        raise


def chat(messages, json_out=False):
    body = {"model": CHAT_MODEL, "messages": messages}
    if json_out:
        body["response_format"] = {"type": "json_object"}
    r = json.loads(http("https://api.openai.com/v1/chat/completions", json.dumps(body).encode(),
                        {"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": "application/json"}))
    return r["choices"][0]["message"]["content"]


def write_scenes(cards, scenes):
    """Writes a scene for every card that lacks one, 25 cards a request, saving as it goes."""
    todo = [c for c in cards if c["id"] not in scenes]
    for i in range(0, len(todo), 25):
        batch = todo[i:i + 25]
        prompt = ("For each idea card below, describe one painting that symbolises its idea, in at most 30 words: "
                  "concrete objects, people or a place, in warm candle-lit light. Never include writing, signs, labels, "
                  "screens, open book pages, letters or numbers. Don't name real brands. Reply as JSON "
                  "{\"<id>\": \"<scene>\"}.\n\n" +
                  "\n".join(f"{c['id']}: {c['title']} — {c['body'][:280]}" for c in batch))
        out = json.loads(chat([{"role": "user", "content": prompt}], json_out=True))
        with lock:
            for c in batch:
                if isinstance(out.get(c["id"]), str) and out[c["id"]].strip():
                    scenes[c["id"]] = out[c["id"]].strip()
            SCENES.write_text(json.dumps(dict(sorted(scenes.items())), indent=1, ensure_ascii=False) + "\n")
        print(f"scenes {min(i + 25, len(todo))}/{len(todo)}", flush=True)


MAX_NEW = [0]  # set by --max-new: no more paid pictures than this in one run


def ideogram(prompt, seed):
    with lock:
        if spent["ideogram"] >= MAX_NEW[0]:
            raise RuntimeError("Ideogram budget for this run is used up (--max-new)")
        spent["ideogram"] += 1
    b = uuid.uuid4().hex
    fields = [("prompt", prompt), ("aspect_ratio", "4x5"), ("rendering_speed", "TURBO"), ("magic_prompt", "OFF"),
              ("style_type", "GENERAL"), ("negative_prompt", NEGATIVE), ("seed", str(seed))]
    body = "".join(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n' for k, v in fields) + f"--{b}--\r\n"
    r = json.loads(http("https://api.ideogram.ai/v1/ideogram-v3/generate", body.encode(),
                        {"Api-Key": os.environ["IDEOGRAM_API_KEY"], "Content-Type": f"multipart/form-data; boundary={b}"}))
    url = r["data"][0]["url"]
    # The link is short-lived and refuses Python's default client, so fetch it with curl straight away.
    return subprocess.run(["curl", "-sS", "-fL", "-A", "Mozilla/5.0", url], check=True, capture_output=True).stdout


def has_lettering(png):
    small = Image.open(io.BytesIO(png)).convert("RGB")
    small.thumbnail((512, 512))
    buf = io.BytesIO()
    small.save(buf, "JPEG", quality=80)
    data = base64.b64encode(buf.getvalue()).decode()
    answer = chat([{"role": "user", "content": [
        {"type": "text", "text": "Does this painting contain any letters, words, writing, signature or fake lettering? "
                                 "Clock numerals don't count. Answer only yes or no."},
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{data}", "detail": "low"}}]}])
    return answer.strip().lower().startswith("y")


def art_for(card, scene, card_images, out, allow_paid=False):
    """(image, layout): the card's own picture when there is one, else saved or new Ideogram art."""
    img = card_images.get(card["id"])
    if img and img.get("type") in REUSE_TYPES and MEDIA:
        raw = fetch(f"{MEDIA}/{img.get('full') or img['file']}")
        if raw:
            with lock:
                spent["reused"] += 1
            return Image.open(io.BytesIO(raw)).convert("RGB"), "wide"
    # Hand-picked art for this card (e.g. the first samples), kept as art/<card-id>.png.
    picked = out / "art" / f"{card['id']}.png"
    raw = picked.read_bytes() if picked.exists() else (fetch(f"{MEDIA}/images/posts/art/{card['id']}.png") if MEDIA else None)
    if raw:
        picked.parent.mkdir(parents=True, exist_ok=True)
        picked.write_bytes(raw)
        with lock:
            spent["kept"] += 1
        return Image.open(io.BytesIO(raw)).convert("RGB"), "tall"
    if not allow_paid:
        raise RuntimeError("needs new art; run with --pay to make it with Ideogram")
    prompt = f"{scene} {STYLE}"
    name = f"{card['id']}-{hashlib.sha256(prompt.encode()).hexdigest()[:12]}.png"
    local = out / "art" / name
    if local.exists():
        return Image.open(local).convert("RGB"), "tall"
    raw = fetch(f"{MEDIA}/images/posts/art/{name}") if MEDIA else None
    if raw:
        with lock:
            spent["kept"] += 1
    else:
        seed = int(hashlib.sha256(card["id"].encode()).hexdigest()[:8], 16) % 2_000_000_000
        raw = ideogram(prompt, seed)
        if has_lettering(raw) and spent["ideogram"] < MAX_NEW[0]:
            with lock:
                spent["retries"] += 1
            raw = ideogram(prompt, seed + 1)
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_bytes(raw)
    return Image.open(io.BytesIO(raw)).convert("RGB"), "tall"


def wrap(draw, text, font, width):
    lines, cur = [], ""
    for word in text.split():
        t = f"{cur} {word}".strip()
        if draw.textlength(t, font=font) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    return lines + [cur]


def shade(top_end, bottom_start, solid_until=0):
    """An alpha ramp: dark at the top for the headline, clear in the middle, dark again for the footer.

    Above solid_until it is fully dark, then it fades out by top_end."""
    g = Image.new("L", (1, H))
    for y in range(H):
        if y < solid_until:
            a = 255
        elif solid_until and y < top_end:
            a = (1 - (y - solid_until) / (top_end - solid_until)) ** 1.6 * 255
        elif y < top_end:
            a = min(1.0, max(0.0, 1.25 - y / (top_end * 0.8))) * 235
        elif y > bottom_start:
            a = (y - bottom_start) / (H - bottom_start) * 230
        else:
            a = 0
        g.putpixel((0, y), int(a))
    return g.resize((W, H))


def compose(card, source, topic_name, art, layout):
    if layout == "tall":  # 4:5 art fills the post
        s = max(W / art.width, H / art.height)
        art = art.resize((round(art.width * s), round(art.height * s)), Image.LANCZOS)
        x = (art.width - W) // 2
        canvas = art.crop((x, 0, x + W, H)).convert("RGBA")
        top_end, solid = H * 0.75, 0
    else:  # a 3:2 card picture sits full width at the bottom, fading into the dark above
        canvas = Image.new("RGBA", (W, H), INK + (255,))
        pic = art.resize((W, round(art.height * W / art.width)), Image.LANCZOS)
        y0 = H - pic.height
        canvas.paste(pic, (0, y0))
        top_end, solid = y0 + pic.height * 0.4, y0
    canvas = Image.alpha_composite(canvas, Image.merge("RGBA", [Image.new("L", (W, H), v) for v in INK] + [shade(top_end, H * 0.80, solid)]))
    d = ImageDraw.Draw(canvas)
    bold, italic = str(FONTS / "Fraunces-SemiBold.ttf"), str(FONTS / "Fraunces-SemiBoldItalic.ttf")
    for size in range(96, 40, -4):
        font = ImageFont.truetype(bold, size)
        lines = wrap(d, card["title"], font, W - 160)
        if len(lines) <= 4 and all(d.textlength(l, font=font) <= W - 160 for l in lines):
            break
    y = 110
    d.text((80, y), topic_name.upper(), font=ImageFont.truetype(bold, 30), fill=AMBER)
    y += 70
    for line in lines:
        d.text((80, y), line, font=font, fill=CREAM)
        y += int(size * 1.12)
    d.rectangle((80, y + 24, 180, y + 28), fill=AMBER)
    authors = [a for a in source.get("authors") or [] if a != "Reborn"]
    credit = f"{source['title']} · {authors[0]}" if authors else source["title"]
    small = ImageFont.truetype(italic, 32)
    while d.textlength(credit, font=small) > W - 330 and small.size > 26:
        small = ImageFont.truetype(italic, small.size - 2)
    if d.textlength(credit, font=small) > W - 330:
        while d.textlength(credit + "…", font=small) > W - 330:
            credit = credit[:-1]
        credit += "…"
    d.text((80, H - 104), credit, font=small, fill=CREAM)
    d.text((W - 80, H - 104), "Reborn", font=ImageFont.truetype(bold, 34), fill=AMBER, anchor="ra")
    return canvas.convert("RGB")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    pick = ap.add_mutually_exclusive_group(required=True)
    pick.add_argument("--cards", nargs="+")
    pick.add_argument("--per-topic", type=int)
    pick.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, help="stop after this many new posts")
    ap.add_argument("--out", type=Path, default=REPO / "content" / ".cache" / "posts")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--free-only", action="store_true", help="only cards whose art costs nothing (reused or already made)")
    ap.add_argument("--pay", action="store_true", help="allow new Ideogram pictures (about $0.03 each)")
    ap.add_argument("--max-new", type=int, default=30, help="most new Ideogram pictures to pay for in this run, retries included")
    args = ap.parse_args()

    MAX_NEW[0] = args.max_new if args.pay else 0
    cards, sources = library()
    names = topics()
    card_images = load(CARD_IMAGES, {"cards": {}})["cards"]
    posts = load(POSTS, {"version": 1, "cards": {}})
    scenes = load(SCENES, {})

    if args.cards:
        chosen = [cards[i] for i in args.cards]
    else:
        todo = [c for c in cards.values() if c["id"] not in posts["cards"]]
        if args.per_topic:
            rng, by_topic = random.Random(7), {}
            for c in sorted(todo, key=lambda c: c["id"]):
                by_topic.setdefault(c["topic"], []).append(c)
            # Prefer cards whose picture can be reused, then a spread of books.
            chosen = []
            for group in by_topic.values():
                rng.shuffle(group)
                group.sort(key=lambda c: (card_images.get(c["id"], {}).get("type") not in REUSE_TYPES))
                chosen += group[:args.per_topic]
        else:
            chosen = todo
    if args.free_only:
        have = {p.stem for p in (args.out / "art").glob("*.png")}
        chosen = [c for c in chosen if card_images.get(c["id"], {}).get("type") in REUSE_TYPES or c["id"] in have]
    if args.limit:
        chosen = chosen[:args.limit]
    print(f"{len(chosen)} posts to make", flush=True)

    if args.pay:
        write_scenes([c for c in chosen if card_images.get(c["id"], {}).get("type") not in REUSE_TYPES], scenes)

    (args.out / "v1").mkdir(parents=True, exist_ok=True)

    def make(card):
        art, layout = art_for(card, scenes.get(card["id"], ""), card_images, args.out, args.pay)
        img = compose(card, sources[card["source_id"]], names.get(card["topic"], card["topic"]), art, layout)
        img.save(args.out / "v1" / f"{card['id']}.jpg", "JPEG", quality=86, optimize=True, progressive=True)
        alt = card_images.get(card["id"], {}).get("caption") if layout == "wide" else scenes.get(card["id"], "")
        with lock:
            posts["cards"][card["id"]] = {"file": f"images/posts/v1/{card['id']}.jpg", "width": W, "height": H, "alt": alt or ""}

    failed = []
    with cf.ThreadPoolExecutor(args.jobs) as pool:
        futures = {pool.submit(make, c): c["id"] for c in chosen}
        for n, f in enumerate(cf.as_completed(futures), 1):
            try:
                f.result()
            except Exception as e:  # keep going; the card is simply left for the next run
                failed.append(futures[f])
                print(f"failed {futures[f]}: {e}", file=sys.stderr, flush=True)
            if n % 25 == 0 or n == len(chosen):
                with lock:
                    POSTS.write_text(json.dumps({"version": 1, "cards": dict(sorted(posts["cards"].items()))}, indent=1, ensure_ascii=False) + "\n")
                print(f"{n}/{len(chosen)} done; {spent}", flush=True)
    POSTS.write_text(json.dumps({"version": 1, "cards": dict(sorted(posts["cards"].items()))}, indent=1, ensure_ascii=False) + "\n")
    print(f"done: {len(posts['cards'])} posts in all; new Ideogram pictures {spent['ideogram']} "
          f"(≈${spent['ideogram'] * 0.03:.2f}), reused card pictures {spent['reused']}, kept art {spent['kept']}, "
          f"lettering retries {spent['retries']}; failed {len(failed)}", flush=True)


if __name__ == "__main__":
    main()

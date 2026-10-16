"""Turn the image thread's manifest into content/images/manifest.json, which the API reads.

    python import_manifest.py /mnt/project-files/images/card-visuals-v1/manifest.json

The source manifest lists one entry per card with absolute R2 URLs. This keeps only the
path inside the media store (images/cards/v1/<card-id>.webp), so the API builds each URL
from MEDIA_BASE_URL like it does for videos and audio. Cards are keyed by id; running it
again with a newer manifest replaces the entries it lists and keeps the rest.
"""
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
TYPES = {"illustration", "3d", "chart", "photo"}


def key(url):
    return urlparse(url).path.lstrip("/") if url else ""


def main(src):
    out = HERE / "manifest.json"
    cards = json.loads(out.read_text())["cards"] if out.exists() else {}
    for e in json.loads(Path(src).read_text()):
        if e["type"] not in TYPES:
            raise SystemExit(f"{e['card_id']}: unknown image type {e['type']!r}")
        entry = {"file": key(e["image"]), "full": key(e.get("image_full")), "type": e["type"],
                 "caption": e.get("caption") or ""}
        for k in ("basis", "source", "credit"):
            if e.get(k):
                entry[k] = e[k]
        cards[e["card_id"]] = entry
    out.write_text(json.dumps({"version": 1, "cards": dict(sorted(cards.items()))}, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(cards)} cards with images")


if __name__ == "__main__":
    main(sys.argv[1])

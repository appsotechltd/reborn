"""Validation of content/library/*.json against content/SCHEMA.md, plus house rules.

Stdlib only, so it runs anywhere Python 3.11+ does. The backend's `reborn seed` applies the
same SCHEMA.md rules; this validator adds the provenance rules (every source is registered).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

SLUG = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CARD_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*--[0-9]{2,3}$")
URL = re.compile(r"^https?://\S+$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

KINDS = {"book", "textbook", "article", "guide", "study", "talk", "podcast", "video"}
LICENCES = {
    "public-domain", "us-gov-public-domain", "cc-by-4.0", "cc-by-3.0",
    "cc-by-sa-4.0", "cc0-1.0", "ogl-3.0", "original-summary",
}
TOPICS = {
    "business", "psychology", "mental-strength", "health", "emotional-intelligence", "personal-development",
    "productivity", "money", "relationships", "dating-marriage", "mindfulness", "faith-wisdom", "leadership",
    "parenting", "communication", "creativity", "learning", "lives-history", "entrepreneurship",
    "heartbreak-healing", "grief-loss", "study-smarter", "skills-mastery", "etiquette",
    "mental-health", "ai-skills", "science", "crime-society", "life-guides",
}
SOURCE_REQUIRED = {"id", "title", "authors", "kind", "url", "licence", "licence_url", "attribution", "retrieved_at"}
SOURCE_FIELDS = SOURCE_REQUIRED | {"publisher", "year", "language", "translator", "notes"}
CARD_REQUIRED = {"id", "topic", "title", "body", "apply_it"}
CARD_FIELDS = CARD_REQUIRED | {"tags", "quote", "locator", "quiz", "health", "language"}
QUIZ_FIELDS = {"question", "options", "answer", "explanation"}


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    # Advisory only: printed, but never fail --strict (e.g. a short source below the 30-card target)
    notes: list[str] = field(default_factory=list)

    def error(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"{where}: {msg}")

    def note(self, where: str, msg: str) -> None:
        self.notes.append(f"{where}: {msg}")


def _str(r: Report, where: str, obj: dict, key: str, max_len: int, required: bool = True) -> str | None:
    v = obj.get(key)
    if v is None:
        if required:
            r.error(where, f"missing {key}")
        return None
    if not isinstance(v, str) or not v.strip():
        r.error(where, f"{key} must be a non-empty string")
        return None
    if len(v) > max_len:
        r.error(where, f"{key} is {len(v)} chars, max {max_len}")
    if v != v.strip():
        r.warn(where, f"{key} has leading or trailing whitespace")
    return v


def words(text: str) -> int:
    return len(text.split())


def validate_source(r: Report, where: str, src: object, file_stem: str) -> dict | None:
    if not isinstance(src, dict):
        r.error(where, "source must be an object")
        return None
    for k in sorted(set(src) - SOURCE_FIELDS):
        r.error(where, f"unknown source field {k!r}")
    sid = _str(r, where, src, "id", 80)
    if sid and not SLUG.match(sid):
        r.error(where, f"source id {sid!r} is not a lowercase slug")
    if sid and sid != file_stem:
        r.error(where, f"source id {sid!r} doesn't match file name {file_stem!r}")
    _str(r, where, src, "title", 300)
    authors = src.get("authors")
    if not isinstance(authors, list) or not authors or not all(isinstance(a, str) and a.strip() for a in authors):
        r.error(where, "authors must be a non-empty list of names")
    if src.get("kind") not in KINDS:
        r.error(where, f"kind {src.get('kind')!r} not one of {sorted(KINDS)}")
    for k in ("url", "licence_url"):
        v = _str(r, where, src, k, 2000)
        if v and not URL.match(v):
            r.error(where, f"{k} is not an http(s) URL")
    lic = src.get("licence")
    if isinstance(lic, str) and "nc" in lic.split("-"):
        r.error(where, f"non-commercial licence {lic!r} is not allowed")
    elif lic not in LICENCES:
        r.error(where, f"licence {lic!r} not one of {sorted(LICENCES)}")
    _str(r, where, src, "attribution", 300)
    for k in ("publisher", "language", "translator", "notes"):
        _str(r, where, src, k, 2000, required=False)
    if "year" in src and (not isinstance(src["year"], int) or isinstance(src["year"], bool)):
        r.error(where, "year must be an integer")
    ra = _str(r, where, src, "retrieved_at", 10)
    if ra:
        try:
            if not DATE.match(ra):
                raise ValueError
            date.fromisoformat(ra)
        except ValueError:
            r.error(where, f"retrieved_at {ra!r} is not a YYYY-MM-DD date")
    return src


def validate_quiz(r: Report, where: str, quiz: object) -> None:
    if not isinstance(quiz, dict):
        r.error(where, "quiz must be an object")
        return
    for k in sorted(set(quiz) - QUIZ_FIELDS):
        r.error(where, f"unknown quiz field {k!r}")
    _str(r, where, quiz, "question", 200)
    _str(r, where, quiz, "explanation", 300, required=False)
    opts = quiz.get("options")
    if not isinstance(opts, list) or not 2 <= len(opts) <= 4:
        r.error(where, "quiz.options must have 2-4 options")
        return
    for i, o in enumerate(opts):
        if not isinstance(o, str) or not o.strip():
            r.error(where, f"quiz.options[{i}] must be a non-empty string")
        elif len(o) > 120:
            r.error(where, f"quiz.options[{i}] is {len(o)} chars, max 120")
    if len({o.strip().lower() for o in opts if isinstance(o, str)}) != len(opts):
        r.error(where, "quiz.options has duplicates")
    ans = quiz.get("answer")
    if not isinstance(ans, int) or isinstance(ans, bool) or not 0 <= ans < len(opts):
        r.error(where, f"quiz.answer {ans!r} is not a valid index into options")


def validate_card(r: Report, where: str, card: object, src: dict) -> None:
    if not isinstance(card, dict):
        r.error(where, "card must be an object")
        return
    for k in sorted(set(card) - CARD_FIELDS):
        r.error(where, f"unknown card field {k!r}")
    cid = _str(r, where, card, "id", 90)
    sid = src.get("id")
    if cid and not CARD_ID.match(cid):
        r.error(where, f"card id {cid!r} must look like <source-id>--NN")
    elif cid and sid and not cid.startswith(f"{sid}--"):
        r.error(where, f"card id {cid!r} must start with {sid}--")
    topic = card.get("topic")
    if topic not in TOPICS:
        r.error(where, f"topic {topic!r} not one of {sorted(TOPICS)}")
    tags = card.get("tags")
    if tags is not None:
        if not isinstance(tags, list) or len(tags) > 8:
            r.error(where, "tags must be a list of at most 8 slugs")
        else:
            for t in tags:
                if not isinstance(t, str) or not SLUG.match(t) or len(t) > 80:
                    r.error(where, f"tag {t!r} is not a lowercase slug")
            if len(set(tags)) != len(tags):
                r.warn(where, "duplicate tags")
    _str(r, where, card, "title", 90)
    body = _str(r, where, card, "body", 1200)
    if body:
        n = words(body)
        if not 25 <= n <= 160:
            r.error(where, f"body is {n} words, must be 25-160")
    _str(r, where, card, "apply_it", 240)
    _str(r, where, card, "locator", 120, required=False)
    _str(r, where, card, "language", 35, required=False)
    quote = _str(r, where, card, "quote", 300, required=False)
    if quote and src.get("licence") == "original-summary":
        r.error(where, "quote not allowed for original-summary sources")
    if quote and any(m in quote for m in '"“”'):
        r.warn(where, "quote contains double quote marks; the apps wrap quotes in them, so use single marks for speech inside")
    if quote and body and quote.strip() in body:
        r.warn(where, "body contains the quote verbatim; the body should be in our own words")
    health = card.get("health", False)
    if not isinstance(health, bool):
        r.error(where, "health must be true or false")
    elif topic == "health" and not health:
        r.error(where, "health must be true when topic is health")
    if "quiz" in card:
        validate_quiz(r, where, card["quiz"])


def validate_file(r: Report, path: Path, seen_ids: dict[str, str], registry: dict | None) -> dict | None:
    where = path.name
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        r.error(where, f"not valid JSON: {e}")
        return None
    if not isinstance(doc, dict):
        r.error(where, "top level must be an object with source and cards")
        return None
    for k in sorted(set(doc) - {"source", "cards"}):
        r.error(where, f"unknown top-level field {k!r}")
    src = validate_source(r, where, doc.get("source"), path.stem)
    if src is None:
        return None
    cards = doc.get("cards")
    if not isinstance(cards, list) or not cards:
        r.error(where, "cards must be a non-empty list")
        return doc
    # Same rule as the Go validator: more than 50 is rejected, fewer than 30 is flagged but allowed
    if len(cards) > 50:
        r.error(where, f"{len(cards)} cards; a source can have at most 50")
    elif len(cards) < 30:
        r.note(where, f"{len(cards)} cards; aim for 30-50 per source")
    for i, card in enumerate(cards):
        cw = f"{where} card {card.get('id', i) if isinstance(card, dict) else i}"
        validate_card(r, cw, card, src)
        cid = card.get("id") if isinstance(card, dict) else None
        if isinstance(cid, str):
            if cid in seen_ids:
                r.error(cw, f"duplicate card id (also in {seen_ids[cid]})")
            seen_ids[cid] = path.name
    titles = [c.get("title", "").strip().lower() for c in cards if isinstance(c, dict)]
    if len(set(titles)) != len(titles):
        r.error(where, "two cards share a title")

    if registry is not None:
        entry = registry.get(src.get("id"))
        if entry is None:
            r.error(where, "source isn't in content/pipeline/sources.toml (record how it was fetched)")
        elif entry.get("licence") != src.get("licence"):
            r.error(where, f"licence {src.get('licence')!r} differs from sources.toml ({entry.get('licence')!r})")
    return doc


def validate_library(library_dir: Path, registry: dict | None) -> tuple[Report, list[dict]]:
    r = Report()
    docs = []
    seen: dict[str, str] = {}
    files = sorted(library_dir.glob("*.json"))
    for path in files:
        doc = validate_file(r, path, seen, registry)
        if doc is not None:
            docs.append(doc)
    return r, docs

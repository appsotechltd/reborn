"""Passages: the normalised paragraphs of a fetched source, and quote matching against them."""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class Passage:
    source_id: str
    n: int
    locator: str
    text: str

    @property
    def id(self) -> str:
        return f"{self.source_id}:{self.n:05d}"


def write_jsonl(path: Path, passages: list[Passage]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for p in passages:
            f.write(json.dumps({"id": p.id, **asdict(p)}, ensure_ascii=False) + "\n")


def read_jsonl(path: Path) -> list[Passage]:
    out = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            out.append(Passage(d["source_id"], d["n"], d["locator"], d["text"]))
    return out


_TRANSLATE = str.maketrans(
    {
        "‘": "'", "’": "'", "‛": "'", "′": "'",
        "“": '"', "”": '"', "‟": '"', "″": '"',
        "–": "-", "—": "-", "―": "-", "‒": "-", "‐": "-", "‑": "-",
        "⁠": "", "­": "", "﻿": "", "​": "",
        "_": "",  # Gutenberg italics markers
    }
)
_ELLIPSIS = re.compile(r"\s*(?:\.\s*\.\s*\.|…)\s*")
_NON_WORD = re.compile(r"[^\w']+")
_QUOTE_MARK = re.compile(r"(?<!\w)'|'(?!\w)")  # a quotation mark, not an apostrophe inside a word


def normalise(text: str) -> str:
    """Reduce text to lowercase words so typography and line wrapping don't affect matching.

    Hyphens become spaces, so "busy-body" matches "busy body" but not "busybody"; that is
    deliberate, as quotes should follow the edition they cite.
    """
    text = unicodedata.normalize("NFKC", text).translate(_TRANSLATE).lower()
    return " ".join(_QUOTE_MARK.sub(" ", _NON_WORD.sub(" ", text)).split())


def quote_segments(quote: str) -> list[str]:
    """Split a quote on ellipses; each segment must appear, in order, in the source."""
    return [s for s in (normalise(p) for p in _ELLIPSIS.split(quote)) if s]


def find_quote(quote: str, passages: list[Passage]) -> Passage | None:
    """Return the passage where the quote starts, or None if it isn't in the source.

    Segments are searched in the whole text joined passage by passage, so a quote may
    run across a paragraph break and ellipses may skip text.
    """
    segments = quote_segments(quote)
    if not segments:
        return None
    starts: list[int] = []
    parts: list[str] = []
    pos = 0
    for p in passages:
        starts.append(pos)
        t = normalise(p.text)
        parts.append(t)
        pos += len(t) + 1
    corpus = " ".join(parts)

    first = corpus.find(segments[0])
    while first != -1:
        cursor = first + len(segments[0])
        ok = True
        for seg in segments[1:]:
            i = corpus.find(seg, cursor)
            # ellipses may skip a little text, not whole chapters
            if i == -1 or i - cursor > 2000:
                ok = False
                break
            cursor = i + len(seg)
        if ok:
            # boundaries: don't match inside a word
            before_ok = first == 0 or corpus[first - 1] == " "
            after_ok = cursor == len(corpus) or corpus[cursor] == " "
            if before_ok and after_ok:
                idx = max(i for i, s in enumerate(starts) if s <= first)
                return passages[idx]
        first = corpus.find(segments[0], first + 1)
    return None

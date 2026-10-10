"""Project Gutenberg plain-text ebooks.

Registry fields: gutenberg_id, optional mirror (a path under raw.githubusercontent.com/GITenberg,
used when gutenberg.org is unreachable), optional start / end (literal lines that bound the body,
to drop front matter such as a table of contents), optional verses (a book name such as "Proverbs":
the text is a Gutenberg Bible book with "20:006:006" verse numbers, and each verse becomes one
passage with a "Proverbs 6:6" locator).
"""

from __future__ import annotations

import re
from pathlib import Path

from .. import http
from ..passages import Passage
from . import FetchResult, LicenceError

PRIMARY = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
MIRROR = "https://raw.githubusercontent.com/GITenberg/{path}"

_START = re.compile(r"^\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*$", re.M | re.I)
_END = re.compile(r"^\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG EBOOK.*$", re.M | re.I)
_ROMAN = re.compile(r"^(?:[IVXLC]+\.?|\d+\.?)$")
_OLD_SMALL_PRINT = re.compile(r"SMALL PRINT!\*\*FOR PUBLIC DOMAIN EBOOKS", re.I)
_VERSE = re.compile(r"^\d+:(\d{3}):(\d{3})\s+", re.M)
_HEADING_WORD = re.compile(r"^(CHAPTER|BOOK|PART|LECTURE|SECTION|LESSON)\b", re.I)


def licence_from_header(header: str, trailer: str = "") -> str:
    h = " ".join(header.split()).lower()
    if "copyrighted project gutenberg" in h:
        raise LicenceError("Gutenberg header marks this ebook as copyrighted")
    if "for the use of anyone anywhere" in h:
        return "public-domain"
    # Older ebooks (pre-2004) carry the licence in a "small print" trailer instead of the header
    if _OLD_SMALL_PRINT.search(trailer):
        return "public-domain"
    raise LicenceError(f"no Project Gutenberg licence header found: {header[:200]!r}")


_SMALL = {"a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "with"}


def title_case(line: str) -> str:
    """Title-case an all-caps heading, keeping roman numerals: "CHAPTER IX. THE WILL" -> "Chapter IX. The Will"."""
    if not line.isupper():
        return line
    out = []
    for i, w in enumerate(line.split()):
        core = w.strip(".,:;!?\"'()")
        if core and re.fullmatch(r"[IVXLC]+", core) and core not in {"I", "C", "L"} or core == "I" and i > 0:
            out.append(w)
        elif i > 0 and core.lower() in _SMALL and not out[-1].endswith((".", ":")):
            out.append(w.lower())
        else:
            out.append(w[:1] + w[1:].lower())
    return " ".join(out)


def _is_heading_line(line: str) -> bool:
    if len(line) > 80 or line.startswith(("--", "\"", "'", "(", "[", "_")):
        return False
    letters = [c for c in line if c.isalpha()]
    return bool(
        _HEADING_WORD.match(line)
        or _ROMAN.match(line)
        or (letters and all(c.isupper() for c in letters) and len(letters) >= 3)
    )


def _is_heading(block: str) -> bool:
    """A block of one to three short heading-like lines, e.g. "CHAPTER I." / "SELF-HELP"."""
    lines = [ln.strip() for ln in block.strip().split("\n")]
    return len(lines) <= 3 and all(_is_heading_line(ln) for ln in lines)


def parse_verses(body: str, source_id: str, book: str) -> list[Passage]:
    """One passage per verse: "20:006:006 Go to the ant..." -> locator "Proverbs 6:6"."""
    marks = list(_VERSE.finditer(body))
    passages = []
    for i, m in enumerate(marks):
        text = " ".join(body[m.end() : marks[i + 1].start() if i + 1 < len(marks) else len(body)].split())
        locator = f"{book} {int(m.group(1))}:{int(m.group(2))}"
        passages.append(Passage(source_id, len(passages) + 1, locator, text))
    return passages


def parse_text(text: str, source_id: str, start: str | None = None, end: str | None = None, verses: str | None = None):
    text = text.replace("\r\n", "\n").lstrip("﻿")
    m_start, m_end = _START.search(text), _END.search(text)
    header = text[: m_start.start()] if m_start else text[:3000]
    licence = licence_from_header(header, text[m_end.end() :] if m_end else "")
    body = text[m_start.end() : m_end.start() if m_end else len(text)] if m_start else text
    if start:
        i = body.find(start)
        if i == -1:
            raise ValueError(f"{source_id}: start marker {start!r} not found")
        body = body[i:]
    if end:
        i = body.find(end)
        if i == -1:
            raise ValueError(f"{source_id}: end marker {end!r} not found")
        body = body[:i]
    if verses:
        return licence, " ".join(header.split())[:600], parse_verses(body, source_id, verses)

    passages: list[Passage] = []
    heading, count = "Front matter", 0
    for block in re.split(r"\n\s*\n", body):
        if not block.strip():
            continue
        if _is_heading(block):
            line = ". ".join(title_case(" ".join(ln.split())).rstrip(".") for ln in block.strip().split("\n"))
            # "CHAPTER I" followed by its title: keep both
            if heading and _HEADING_WORD.match(heading) and count == 0 and not _HEADING_WORD.match(line):
                heading = f"{heading}. {line}"
            else:
                heading = line
            count = 0
            continue
        para = " ".join(block.split())
        if para.startswith("[Illustration") or len(para) < 2:
            continue
        count += 1
        passages.append(Passage(source_id, len(passages) + 1, f"{heading} ¶{count}", para))
    return licence, " ".join(header.split())[:600], passages


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    gid = entry["gutenberg_id"]
    urls = [PRIMARY.format(id=gid)]
    if entry.get("mirror"):
        urls.append(MIRROR.format(path=entry["mirror"]))
    url, data = http.get_first(urls, cache_dir)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    licence, evidence, passages = parse_text(text, entry["id"], entry.get("start"), entry.get("end"), entry.get("verses"))
    return FetchResult(licence, evidence, url, passages)

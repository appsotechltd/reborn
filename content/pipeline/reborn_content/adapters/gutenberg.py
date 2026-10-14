"""Project Gutenberg plain-text ebooks.

Registry fields: gutenberg_id (fetched from gutenberg.org, falling back to its gutenberg.pglaf.org
mirror), optional mirror (a path under raw.githubusercontent.com/GITenberg, also used when
gutenberg.org is unreachable), optional start / end (literal lines that bound the body,
to drop front matter such as a table of contents), optional verses (a book name such as "Proverbs":
the text is a Gutenberg Bible book with "20:006:006" verse numbers, and each verse becomes one
passage with a "Proverbs 6:6" locator), optional heading_prefix (a block starting with it, such as
"Chapter ", is a heading even when it wraps onto a mixed-case second line).
"""

from __future__ import annotations

import re
from pathlib import Path

from .. import http
from ..passages import Passage
from . import FetchResult, LicenceError

PRIMARY = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
PGLAF = "https://gutenberg.pglaf.org/cache/epub/{id}/pg{id}.txt"  # Gutenberg's own mirror: the same file
MIRROR = "https://raw.githubusercontent.com/GITenberg/{path}"

_START = re.compile(r"^\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*$", re.M | re.I)
_END = re.compile(r"^\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG EBOOK.*$", re.M | re.I)
_ROMAN = re.compile(r"^(?:[IVXLC]+\.?|\d+\.?)$")
_OLD_SMALL_PRINT = re.compile(r"SMALL PRINT!\*\*FOR PUBLIC DOMAIN E(BOOKS|TEXTS)", re.I)
_PAGE_MARK = re.compile(r"\s*\{\d+[a-z]?\}")  # "{47a}" page/footnote anchors in some ebooks
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
            # capitalise the first letter even after an opening quote: "‘TREASURE" -> "‘Treasure"
            j = next((k for k, ch in enumerate(w) if ch.isalpha()), 0)
            out.append(w[: j + 1] + w[j + 1 :].lower())
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


def _locator(heading: str, count: int) -> str:
    """Keep locators within the 120-char limit: a long run-on heading
    ("Chapter VI. The Struggle for Means to Work. The. Burden of Celebrity. ...") keeps its first two parts."""
    locator = f"{heading} ¶{count}"
    if len(locator) <= 120:
        return locator
    return f"{'. '.join(heading.split('. ')[:2])[:110].rstrip()} ¶{count}"


def parse_verses(body: str, source_id: str, book: str) -> list[Passage]:
    """One passage per verse: "20:006:006 Go to the ant..." -> locator "Proverbs 6:6"."""
    marks = list(_VERSE.finditer(body))
    passages = []
    for i, m in enumerate(marks):
        text = " ".join(body[m.end() : marks[i + 1].start() if i + 1 < len(marks) else len(body)].split())
        locator = f"{book} {int(m.group(1))}:{int(m.group(2))}"
        passages.append(Passage(source_id, len(passages) + 1, locator, text))
    return passages


def parse_text(
    text: str,
    source_id: str,
    start: str | None = None,
    end: str | None = None,
    verses: str | None = None,
    section_marker: str | None = None,
    section_label: str | None = None,
    heading_prefix: str | None = None,
):
    text = text.replace("\r\n", "\n").lstrip("﻿")
    m_start, m_end = _START.search(text), _END.search(text)
    header = text[: m_start.start()] if m_start else text[:3000]
    # Very old etexts (1990s) have neither marker; their "small print" licence sits near the top
    licence = licence_from_header(header, text[m_end.end() :] if m_end else text if not m_start else "")
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
    heading, count, sections = "Front matter", 0, 0
    for block in re.split(r"\n\s*\n", body):
        if not block.strip():
            continue
        # section_marker: numbered sections whose heading line is followed by a mixed-case subtitle,
        # e.g. "A DISCOURSE / Delivered at the Opening of..." -> "Discourse 1"
        if section_marker and block.strip().split("\n")[0].strip() == section_marker:
            sections += 1
            heading, count = f"{section_label or title_case(section_marker)} {sections}", 0
            continue
        unmarked = _PAGE_MARK.sub("", block)
        # heading_prefix: mixed-case headings that wrap onto a second line, e.g.
        # "Chapter I: The Extent Of The Empire In The Age Of The / Antonines.—Part I."
        if heading_prefix and unmarked.strip().startswith(heading_prefix) and len(unmarked.strip()) <= 160:
            heading, count = " ".join(unmarked.split()).rstrip("."), 0
            continue
        if _is_heading(unmarked):
            line = ". ".join(title_case(" ".join(ln.split())).rstrip(".") for ln in unmarked.strip().split("\n"))
            line = line.strip("#").strip()  # "#What Is Apperception?#" sub-headings in some etexts
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
        passages.append(Passage(source_id, len(passages) + 1, _locator(heading, count), para))
    return licence, " ".join(header.split())[:600], passages


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    gid = entry["gutenberg_id"]
    urls = [PRIMARY.format(id=gid), PGLAF.format(id=gid)]
    if entry.get("mirror"):
        # prefer_mirror: the cards were checked against the mirror's edition, which can differ from gutenberg.org's
        urls.insert(0 if entry.get("prefer_mirror") else 1, MIRROR.format(path=entry["mirror"]))
    url, data = http.get_first(urls, cache_dir)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    licence, evidence, passages = parse_text(text, entry["id"], entry.get("start"), entry.get("end"), entry.get("verses"), entry.get("section_marker"), entry.get("section_label"), entry.get("heading_prefix"))
    return FetchResult(licence, evidence, url, passages)

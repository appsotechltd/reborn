"""Wikisource pages, read from their raw wikitext (en.wikisource.org/w/index.php?action=raw).

Registry fields: page (e.g. "My_Inventions"), optional lang (default "en").

The licence comes from the page's own PD-* template, so a page without one is refused.
Sections are its == headings ==; a heading like "I. My Early Life." becomes the
locator "Part I. My Early Life".
"""

from __future__ import annotations

import re
from pathlib import Path

from .. import http
from ..passages import Passage
from . import FetchResult, LicenceError

RAW = "https://{lang}.wikisource.org/w/index.php?title={page}&action=raw"
PAGE = "https://{lang}.wikisource.org/wiki/{page}"

_PD = re.compile(r"\{\{\s*(PD-[\w-]+)[^}]*\}\}", re.I)
_HEADING = re.compile(r"^==\s*(.+?)\s*==\s*$")
_PART = re.compile(r"^([IVXLC]+)\.\s+(.+?)\.?$")
_MINOR = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"}


def licence_from_text(text: str) -> tuple[str, str]:
    m = _PD.search(text)
    if not m:
        raise LicenceError("no public-domain template on the page")
    return "public-domain", m.group(0)


def clean(line: str) -> str:
    line = re.sub(r"<ref[^>]*/>|<ref.*?</ref>", "", line)
    line = re.sub(r"<[^>]+>", "", line)
    line = re.sub(r"\{\{[^{}]*\}\}", "", line)
    line = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", line)
    line = line.replace("'''", "").replace("''", "")
    return " ".join(line.split())


def section_name(heading: str) -> str:
    heading = clean(heading)
    m = _PART.match(heading)
    if not m:
        return heading.rstrip(".")
    words = m.group(2).split()
    words = [w if i == 0 or w.lower() not in _MINOR else w.lower() for i, w in enumerate(words)]
    return f"Part {m.group(1)}. {' '.join(words)}"


def parse_text(text: str, source_id: str) -> list[Passage]:
    out: list[Passage] = []
    section, count = None, 0
    for raw in text.splitlines():
        h = _HEADING.match(raw.strip())
        if h:
            section, count = section_name(h.group(1)), 0
            continue
        if section is None:
            continue  # title page and contents
        line = clean(raw)
        if not line:
            continue
        count += 1
        out.append(Passage(source_id, len(out) + 1, f"{section} ¶{count}", line))
    return out


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    lang, page = entry.get("lang", "en"), entry["page"]
    text = http.get(RAW.format(lang=lang, page=page), cache_dir).decode("utf-8")
    licence, evidence = licence_from_text(text)
    return FetchResult(licence, evidence, PAGE.format(lang=lang, page=page), parse_text(text, entry["id"]))

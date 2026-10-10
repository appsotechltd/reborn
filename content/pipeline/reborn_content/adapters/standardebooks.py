"""Standard Ebooks: proofread public-domain ebooks, source XHTML on GitHub.

Registry fields: repo (e.g. "marcus-aurelius_meditations_george-long"), optional branch,
optional files (XHTML file names to keep, in spine order; default: all bodymatter files).
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

from .. import http
from ..passages import Passage
from . import FetchResult, LicenceError

RAW = "https://raw.githubusercontent.com/standardebooks/{repo}/{branch}/src/epub/{path}"
NS = {
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
    "x": "http://www.w3.org/1999/xhtml",
    "epub": "http://www.idpf.org/2007/ops",
}
X = "{http://www.w3.org/1999/xhtml}"
EPUB_TYPE = "{http://www.idpf.org/2007/ops}type"
HEADINGS = {f"{X}h{i}" for i in range(1, 7)} | {f"{X}hgroup", f"{X}header"}


def _space(s: str) -> str:
    return " ".join(s.split())


def licence_from_rights(rights: str) -> str:
    r = rights.lower()
    if "public domain" in r:
        return "public-domain"
    raise LicenceError(f"Standard Ebooks rights statement isn't a public-domain one: {rights[:200]!r}")


def _text(el: ET.Element) -> str:
    """Text of an element, skipping footnote reference links."""
    parts: list[str] = []

    def walk(e: ET.Element) -> None:
        if e.tag == f"{X}a" and "noteref" in e.get(EPUB_TYPE, ""):
            if e.tail:
                parts.append(e.tail)
            return
        if e.tag == f"{X}br":
            parts.append(" ")
        if e.text:
            parts.append(e.text)
        for c in e:
            walk(c)
        if e.tail:
            parts.append(e.tail)

    if el.text:
        parts.append(el.text)
    for c in el:
        walk(c)
    return _space("".join(parts))


def _short(title: str, limit: int = 40) -> str:
    if len(title) <= limit:
        return title
    return title[:limit].rsplit(" ", 1)[0] + "…"


def _heading(section: ET.Element) -> str | None:
    """A short heading for locators: "Book II", "IX", "I. Laying Plans", "Self-Reliance".

    Epigraphs in a <header> and long subtitles in an <hgroup> are left out so locators stay short.
    """
    for child in section:
        if child.tag in HEADINGS:
            if child.tag.startswith(f"{X}h") and child.tag[-1].isdigit():
                return _text(child).rstrip(".") or None
            h = next((e for e in child.iter() if e.tag.startswith(f"{X}h") and e.tag[-1].isdigit()), None)
            if h is None:
                return None
            label = _text(h).rstrip(".")
            sub = next((e for e in child.iter() if e.tag == f"{X}p" and "title" in e.get(EPUB_TYPE, "")), None)
            if sub is not None and re.fullmatch(r"[IVXLC]+|\d+", label):
                label = f"{label}. {_short(_text(sub).rstrip('.'))}"
            return label or None
        if child.tag == f"{X}p":
            break
    return None


def parse_xhtml(
    data: bytes, source_id: str, start_n: int, fallback_title: str, headings: dict[str, list[str]] | None = None
) -> list[Passage]:
    """Paragraphs of one XHTML file. headings maps section id -> heading trail, shared across files
    so a chapter split into its own file (data-parent="book-1") still gets "Book I" in its locator."""
    headings = {} if headings is None else headings
    root = ET.fromstring(data)
    body = root.find(f"{X}body")
    if body is None:
        return []
    out: list[Passage] = []

    def walk(el: ET.Element, trail: list[str], counter: list[int]) -> None:
        for child in el:
            if child.tag == f"{X}section" or child.tag == f"{X}article":
                h = _heading(child)
                base = trail or headings.get(child.get("data-parent", ""), [])
                sub = base + ([h] if h else [])
                if child.get("id"):
                    headings[child.get("id")] = sub
                walk(child, sub, [0])
            elif child.tag == f"{X}p":
                text = _text(child)
                if not text:
                    continue
                counter[0] += 1
                where = ", ".join(trail) if trail else fallback_title
                out.append(Passage(source_id, start_n + len(out), f"{where} ¶{counter[0]}", text))
            elif child.tag in HEADINGS:
                continue
            else:
                walk(child, trail, counter)

    walk(body, [], [0])
    return out


def _is_bodymatter(data: bytes) -> bool:
    head = data[:4000].decode("utf-8", "replace")
    return bool(re.search(r'epub:type="[^"]*bodymatter', head))


def manifest_spine(spine: list[str], wanted: list[str] | None) -> list[str]:
    """Files to read: the wanted ones, plus earlier files whose headings they may inherit."""
    if not wanted:
        return spine
    last = max(i for i, h in enumerate(spine) if Path(h).name in wanted)
    return spine[: last + 1]


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    repo, branch = entry["repo"], entry.get("branch", "master")
    opf_url = RAW.format(repo=repo, branch=branch, path="content.opf")
    opf = ET.fromstring(http.get(opf_url, cache_dir))
    rights_el = opf.find(".//dc:rights", NS)
    if rights_el is None or not (rights_el.text or "").strip():
        raise LicenceError(f"{entry['id']}: no dc:rights in {opf_url}")
    rights = _space(rights_el.text)
    licence = licence_from_rights(rights)

    manifest = {i.get("id"): i.get("href") for i in opf.iterfind(".//opf:manifest/opf:item", NS)}
    spine = [manifest[r.get("idref")] for r in opf.iterfind(".//opf:spine/opf:itemref", NS)]
    wanted = entry.get("files")
    if wanted:
        names = {Path(h).name: h for h in spine}
        missing = [f for f in wanted if f not in names]
        if missing:
            raise ValueError(f"{entry['id']}: files not in spine: {missing}")

    passages: list[Passage] = []
    headings: dict[str, list[str]] = {}
    for href in manifest_spine(spine, wanted):
        data = http.get(RAW.format(repo=repo, branch=branch, path=href), cache_dir)
        if not _is_bodymatter(data):
            continue
        title = Path(href).stem.replace("-", " ").title()
        found = parse_xhtml(data, entry["id"], len(passages) + 1, title, headings)
        if not wanted or Path(href).name in wanted:
            passages += found
    return FetchResult(licence, rights, f"https://github.com/standardebooks/{repo}", passages)

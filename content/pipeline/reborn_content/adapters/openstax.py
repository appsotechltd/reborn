"""OpenStax textbooks, from their CNXML sources on GitHub (github.com/openstax/osbooks-*).

Registry fields: repo (e.g. "osbooks-psychology"), collection (e.g. "psychology-2e"),
optional branch, optional chapters (chapter titles to keep; default all).

Most OpenStax books moved to CC BY-NC-SA 4.0, which this project can't use, so the licence
gate here matters: it reads <md:license> from the collection and refuses anything NC.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path

from .. import http
from ..passages import Passage
from . import FetchResult, LicenceError

RAW = "https://raw.githubusercontent.com/openstax/{repo}/{branch}/{path}"
COL = "{http://cnx.rice.edu/collxml}"
MD = "{http://cnx.rice.edu/mdml}"
CNX = "{http://cnx.rice.edu/cnxml}"

LICENCES = {
    "creativecommons.org/licenses/by/4.0": "cc-by-4.0",
    "creativecommons.org/licenses/by/3.0": "cc-by-3.0",
    "creativecommons.org/licenses/by-sa/4.0": "cc-by-sa-4.0",
}


def licence_from_url(url: str) -> str:
    key = url.split("://", 1)[-1].rstrip("/")
    if "-nc" in key:
        raise LicenceError(f"non-commercial licence: {url}")
    if key not in LICENCES:
        raise LicenceError(f"unrecognised licence: {url}")
    return LICENCES[key]


def read_collection(data: bytes) -> tuple[str, str, list[tuple[str, str]]]:
    """Return (title, licence url, [(chapter title, module id)])."""
    root = ET.fromstring(data)
    lic = root.find(f".//{MD}license")
    title_el = root.find(f".//{MD}title")
    modules: list[tuple[str, str]] = []

    def walk(el: ET.Element, chapter: str) -> None:
        for child in el:
            if child.tag == f"{COL}subcollection":
                t = child.find(f"{MD}title")
                walk(child, t.text.strip() if t is not None and t.text else chapter)
            elif child.tag == f"{COL}module":
                modules.append((chapter, child.get("document")))
            else:
                walk(child, chapter)

    content = root.find(f"{COL}content")
    if content is not None:
        walk(content, "Front matter")
    url = lic.get("url", "") if lic is not None else ""
    return (title_el.text if title_el is not None else ""), url, modules


def parse_module(data: bytes, source_id: str, chapter: str, start_n: int) -> list[Passage]:
    root = ET.fromstring(data)
    title_el = root.find(f"{CNX}title")
    title = " ".join((title_el.text or "").split()) if title_el is not None else ""
    out = []
    for i, para in enumerate(root.iter(f"{CNX}para"), 1):
        text = " ".join("".join(para.itertext()).split())
        if text:
            where = f"{chapter}: {title}" if title else chapter
            out.append(Passage(source_id, start_n + len(out), f"{where} ¶{i}", text))
    return out


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    repo, branch = entry["repo"], entry.get("branch", "main")
    col_url = RAW.format(repo=repo, branch=branch, path=f"collections/{entry['collection']}.collection.xml")
    title, lic_url, modules = read_collection(http.get(col_url, cache_dir))
    licence = licence_from_url(lic_url)
    keep = set(entry.get("chapters") or [])
    passages: list[Passage] = []
    for chapter, mid in modules:
        if keep and chapter not in keep:
            continue
        data = http.get(RAW.format(repo=repo, branch=branch, path=f"modules/{mid}/index.cnxml"), cache_dir)
        passages += parse_module(data, entry["id"], chapter, len(passages) + 1)
    return FetchResult(licence, f"{title}: {lic_url}", f"https://github.com/openstax/{repo}", passages)


def check_licence(entry: dict, cache_dir: Path | None) -> tuple[str, str]:
    """Return (licence code or 'rejected', licence url) without fetching modules."""
    repo, branch = entry["repo"], entry.get("branch", "main")
    col_url = RAW.format(repo=repo, branch=branch, path=f"collections/{entry['collection']}.collection.xml")
    _, lic_url, _ = read_collection(http.get(col_url, cache_dir))
    try:
        return licence_from_url(lic_url), lic_url
    except LicenceError:
        return "rejected", lic_url

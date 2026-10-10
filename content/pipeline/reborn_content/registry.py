"""The source registry (sources.toml): how each library source is fetched, and its expected licence."""

from __future__ import annotations

import tomllib
from pathlib import Path

ADAPTERS = {"standardebooks", "gutenberg", "openstax", "web", "summary"}


class RegistryError(ValueError):
    pass


def load(path: Path) -> tuple[dict[str, dict], dict[str, dict]]:
    """Return (sources, candidates), each keyed by id."""
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    sources: dict[str, dict] = {}
    for e in data.get("source", []):
        _check(e, sources)
        sources[e["id"]] = e
    candidates: dict[str, dict] = {}
    for e in data.get("candidate", []):
        _check(e, candidates)
        candidates[e["id"]] = e
    return sources, candidates


def _check(e: dict, seen: dict) -> None:
    sid = e.get("id")
    if not sid:
        raise RegistryError(f"entry without id: {e}")
    if sid in seen:
        raise RegistryError(f"duplicate registry id {sid!r}")
    if e.get("adapter") not in ADAPTERS:
        raise RegistryError(f"{sid}: adapter must be one of {sorted(ADAPTERS)}")
    if "licence" not in e:
        raise RegistryError(f"{sid}: missing licence")
    if (e["adapter"] == "summary") != (e["licence"] == "original-summary"):
        raise RegistryError(f"{sid}: summary sources, and only they, use the original-summary licence")
    required = {
        "standardebooks": ["repo"],
        "gutenberg": ["gutenberg_id"],
        "openstax": ["repo", "collection"],
        "web": ["url"],
        "summary": ["url"],
    }[e["adapter"]]
    for k in required:
        if k not in e:
            raise RegistryError(f"{sid}: {e['adapter']} entries need {k}")

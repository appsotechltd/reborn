"""Source adapters. Each turns one registry entry into passages plus the licence it found upstream."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from ..passages import Passage


class LicenceError(RuntimeError):
    """The upstream licence is missing, non-commercial, or doesn't match the registry."""


@dataclass
class FetchResult:
    licence: str  # one of the SCHEMA.md licence codes
    evidence: str  # the upstream text the licence was read from
    fetched_from: str
    passages: list[Passage] = field(default_factory=list)


def fetch(entry: dict, cache_dir: Path | None) -> FetchResult:
    from . import gutenberg, openstax, standardebooks, wikisource

    adapters = {
        "standardebooks": standardebooks.fetch,
        "gutenberg": gutenberg.fetch,
        "openstax": openstax.fetch,
        "wikisource": wikisource.fetch,
    }
    name = entry["adapter"]
    if name not in adapters:
        raise ValueError(f"{entry['id']}: adapter {name!r} can't be fetched automatically")
    result = adapters[name](entry, cache_dir)
    if result.licence != entry["licence"]:
        raise LicenceError(
            f"{entry['id']}: registry says {entry['licence']} but upstream says {result.licence} "
            f"({result.evidence[:120]!r})"
        )
    if not result.passages:
        raise RuntimeError(f"{entry['id']}: no passages extracted from {result.fetched_from}")
    return result


FETCHABLE = {"standardebooks", "gutenberg", "openstax", "wikisource"}

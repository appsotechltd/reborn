"""Command line: python -m reborn_content <command>. Run from content/pipeline."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from . import BUILD_DIR, CACHE_DIR, LIBRARY_DIR, PASSAGES_DIR, REGISTRY_PATH, adapters, registry
from .passages import find_quote, read_jsonl, write_jsonl
from .schema import validate_library


def _passages_path(sid: str) -> Path:
    return PASSAGES_DIR / f"{sid}.jsonl"


def cmd_fetch(args) -> int:
    sources, _ = registry.load(REGISTRY_PATH)
    ids = args.ids or [s for s, e in sources.items() if e["adapter"] in adapters.FETCHABLE]
    failed = 0
    for sid in ids:
        entry = sources.get(sid)
        if entry is None:
            print(f"✗ {sid}: not in sources.toml", file=sys.stderr)
            failed += 1
            continue
        if entry["adapter"] not in adapters.FETCHABLE:
            print(f"- {sid}: {entry['adapter']} sources are read by hand ({entry['url']})")
            continue
        if _passages_path(sid).exists() and not args.force:
            print(f"· {sid}: already fetched")
            continue
        try:
            res = adapters.fetch(entry, None if args.no_cache else CACHE_DIR)
        except Exception as e:  # noqa: BLE001 - report every source, then fail
            print(f"✗ {sid}: {e}", file=sys.stderr)
            failed += 1
            continue
        write_jsonl(_passages_path(sid), res.passages)
        words = sum(len(p.text.split()) for p in res.passages)
        print(f"✓ {sid}: {len(res.passages)} passages, {words} words, {res.licence} ({res.fetched_from})")
    return 1 if failed else 0


def cmd_validate(args) -> int:
    sources, _ = registry.load(REGISTRY_PATH)
    report, docs = validate_library(Path(args.library), sources)
    for w in report.warnings:
        print(f"warning: {w}")
    for e in report.errors:
        print(f"error: {e}", file=sys.stderr)
    cards = sum(len(d.get("cards", [])) for d in docs)
    print(f"{len(docs)} sources, {cards} cards, {len(report.errors)} errors, {len(report.warnings)} warnings")
    if report.errors or (args.strict and report.warnings):
        return 1
    return 0


def cmd_verify(args) -> int:
    sources, _ = registry.load(REGISTRY_PATH)
    _, docs = validate_library(Path(args.library), sources)
    errors, warnings, checked = [], [], 0
    for doc in docs:
        sid = doc["source"]["id"]
        quoted = [c for c in doc.get("cards", []) if isinstance(c, dict) and c.get("quote")]
        if not quoted:
            continue
        entry = sources.get(sid)
        if entry is None or entry["adapter"] not in adapters.FETCHABLE:
            for c in quoted:
                errors.append(f"{c['id']}: has a quote but {sid} can't be fetched to check it")
            continue
        path = _passages_path(sid)
        if not path.exists():
            if not args.fetch:
                errors.append(f"{sid}: not fetched; run `fetch {sid}` or pass --fetch")
                continue
            res = adapters.fetch(entry, CACHE_DIR)
            write_jsonl(path, res.passages)
        passages = read_jsonl(path)
        changed = False
        for c in quoted:
            checked += 1
            hit = find_quote(c["quote"], passages)
            if hit is None:
                errors.append(f"{c['id']}: quote not found in {sid}: {c['quote'][:80]!r}")
            elif c.get("locator") not in (hit.locator, hit.locator.rsplit(" ¶", 1)[0]):
                if args.fix_locators:
                    _set_locator(c, hit.locator)
                    changed = True
                elif c.get("locator"):
                    warnings.append(f"{c['id']}: locator {c['locator']!r} but quote is at {hit.locator!r}")
                else:
                    warnings.append(f"{c['id']}: no locator; quote is at {hit.locator!r}")
        if changed:
            lib = Path(args.library) / f"{sid}.json"
            lib.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"updated locators in {lib.name}")
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    print(f"{checked} quotes checked, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors or (args.strict and warnings) else 0


def _set_locator(card: dict, locator: str) -> None:
    """Set card["locator"], placing a new key straight after "quote" to keep files tidy."""
    if "locator" in card:
        card["locator"] = locator
        return
    items = list(card.items())
    card.clear()
    for k, v in items:
        card[k] = v
        if k == "quote":
            card["locator"] = locator


def cmd_licences(args) -> int:
    from .adapters import openstax

    _, candidates = registry.load(REGISTRY_PATH)
    for cid, e in candidates.items():
        if e["adapter"] != "openstax":
            continue
        try:
            code, url = openstax.check_licence(e, None)
        except Exception as ex:  # noqa: BLE001
            code, url = "error", str(ex)
        print(f"{cid:45} {code:12} {url}")
    return 0


def cmd_export(args) -> int:
    """Write the RAG corpus: one record per card and per source passage, each with its credit line."""
    sources, _ = registry.load(REGISTRY_PATH)
    report, docs = validate_library(Path(args.library), sources)
    if report.errors:
        print("library has errors; run validate", file=sys.stderr)
        return 1
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    n_cards = n_passages = 0
    with (out / "cards.jsonl").open("w", encoding="utf-8") as f:
        for doc in docs:
            src = doc["source"]
            for c in doc["cards"]:
                text = f"{c['title']}\n\n{c['body']}"
                if c.get("quote"):
                    text += f"\n\n\"{c['quote']}\""
                text += f"\n\nApply it: {c['apply_it']}"
                rec = {
                    "id": c["id"], "kind": "card", "source_id": src["id"], "topic": c["topic"],
                    "title": c["title"], "text": text, "attribution": src["attribution"],
                    "url": src["url"], "licence": src["licence"], "health": c.get("health", False),
                }
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                n_cards += 1
    with (out / "passages.jsonl").open("w", encoding="utf-8") as f:
        for doc in docs:
            src = doc["source"]
            path = _passages_path(src["id"])
            if not path.exists():
                continue
            for p in read_jsonl(path):
                rec = {
                    "id": p.id, "kind": "passage", "source_id": src["id"], "locator": p.locator,
                    "text": p.text, "attribution": src["attribution"], "url": src["url"],
                    "licence": src["licence"],
                }
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                n_passages += 1
    print(f"wrote {n_cards} cards and {n_passages} passages to {out}")
    return 0


def cmd_stats(args) -> int:
    sources, _ = registry.load(REGISTRY_PATH)
    _, docs = validate_library(Path(args.library), sources)
    by_topic: Counter = Counter()
    by_licence: Counter = Counter()
    rows = []
    for doc in docs:
        src, cards = doc["source"], doc.get("cards", [])
        by_licence[src["licence"]] += len(cards)
        topics = Counter(c.get("topic") for c in cards)
        by_topic.update(topics)
        quotes = sum(1 for c in cards if c.get("quote"))
        quizzes = sum(1 for c in cards if c.get("quiz"))
        rows.append((src["id"], src["title"], ", ".join(src["authors"]), src["licence"], len(cards), quotes, quizzes,
                     ", ".join(t for t, _ in topics.most_common())))
    total = sum(r[4] for r in rows)
    if args.markdown:
        print("# Reborn starter library\n")
        print("Generated by `python -m reborn_content stats --markdown` from `content/library/`. Do not edit by hand.\n")
        print(f"**{len(rows)} sources, {total} cards.**\n")
        print("| Topic | Cards |\n|---|---|")
        for t, n in sorted(by_topic.items(), key=lambda x: (-x[1], x[0])):
            print(f"| {t} | {n} |")
        print("\n| Licence | Cards |\n|---|---|")
        for lic, n in sorted(by_licence.items(), key=lambda x: (-x[1], x[0])):
            print(f"| {lic} | {n} |")
        print("\n| Source | Title | Author | Licence | Cards | Quotes | Quizzes | Topics |\n|---|---|---|---|---|---|---|---|")
        for r in rows:
            print("| " + " | ".join(str(x) for x in r) + " |")
    else:
        print(f"{len(rows)} sources, {total} cards")
        for t, n in by_topic.most_common():
            print(f"  {t:24} {n}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="reborn_content", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="download sources and write build/passages/<id>.jsonl")
    f.add_argument("ids", nargs="*", help="source ids (default: every fetchable source)")
    f.add_argument("--force", action="store_true", help="re-extract even if passages exist")
    f.add_argument("--no-cache", action="store_true", help="don't read or write the HTTP cache")
    f.set_defaults(func=cmd_fetch)

    for name, func, helptext in [
        ("validate", cmd_validate, "check library files against SCHEMA.md and the registry"),
        ("verify", cmd_verify, "check every quote appears verbatim in its fetched source"),
        ("stats", cmd_stats, "summarise the library"),
        ("export", cmd_export, "write the RAG corpus (cards + passages) for the AI agent"),
    ]:
        s = sub.add_parser(name, help=helptext)
        s.add_argument("--library", default=str(LIBRARY_DIR))
        s.set_defaults(func=func)
        if name in ("validate", "verify"):
            s.add_argument("--strict", action="store_true", help="treat warnings as errors")
        if name == "verify":
            s.add_argument("--fetch", action="store_true", help="fetch sources that haven't been fetched")
            s.add_argument("--fix-locators", action="store_true", help="rewrite each locator to where its quote is")
        if name == "stats":
            s.add_argument("--markdown", action="store_true")
        if name == "export":
            s.add_argument("--out", default=str(BUILD_DIR / "rag"))

    lc = sub.add_parser("licences", help="re-check the upstream licence of candidate sources")
    lc.set_defaults(func=cmd_licences)

    args = p.parse_args(argv)
    return args.func(args)

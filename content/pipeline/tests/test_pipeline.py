"""Offline tests for the content pipeline. Run from content/pipeline: python -m unittest -v"""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from reborn_content import LIBRARY_DIR, REGISTRY_PATH, adapters, registry
from reborn_content.adapters import LicenceError, gutenberg, openstax, standardebooks
from reborn_content.passages import Passage, find_quote, normalise
from reborn_content.schema import validate_library

FIX = Path(__file__).parent / "fixtures"


def fake_http(mapping: dict[str, str]):
    """Patch http.get so URLs ending with a key return that fixture file."""

    def get(url, cache_dir, **_):
        for suffix, name in mapping.items():
            if url.endswith(suffix):
                return (FIX / name).read_bytes()
        raise AssertionError(f"unexpected fetch {url}")

    return mock.patch("reborn_content.http.get", side_effect=get)


class StandardEbooksTest(unittest.TestCase):
    ENTRY = {"id": "meditations", "adapter": "standardebooks", "repo": "x_y", "licence": "public-domain"}

    def fetch(self, entry):
        with fake_http({
            "content.opf": "se_content.opf",
            "titlepage.xhtml": "se_titlepage.xhtml",
            "book-2.xhtml": "se_book-2.xhtml",
        }):
            return adapters.fetch(entry, None)

    def test_extracts_bodymatter_paragraphs_with_locators(self):
        res = self.fetch(self.ENTRY)
        self.assertEqual(res.licence, "public-domain")
        self.assertEqual([p.locator for p in res.passages], ["Book II ¶1", "Book II ¶2"])
        self.assertNotIn("Marcus Aurelius", " ".join(p.text for p in res.passages))  # titlepage skipped

    def test_drops_footnote_references(self):
        text = self.fetch(self.ENTRY).passages[0].text
        self.assertIn("like hands. To act", text)
        self.assertNotIn("24", text)

    def test_files_filter(self):
        res = self.fetch({**self.ENTRY, "files": ["book-2.xhtml"]})
        self.assertEqual(len(res.passages), 2)

    def test_unknown_file_is_an_error(self):
        with self.assertRaises(ValueError):
            self.fetch({**self.ENTRY, "files": ["book-9.xhtml"]})

    def test_registry_licence_must_match_upstream(self):
        with self.assertRaises(LicenceError):
            self.fetch({**self.ENTRY, "licence": "cc-by-4.0"})

    def test_rights_without_public_domain_rejected(self):
        with self.assertRaises(LicenceError):
            standardebooks.licence_from_rights("All rights reserved.")


class GutenbergTest(unittest.TestCase):
    def test_strips_boilerplate_and_tracks_headings(self):
        text = (FIX / "gutenberg_pd.txt").read_text()
        licence, _, passages = gutenberg.parse_text(text, "allen")
        self.assertEqual(licence, "public-domain")
        body = [p for p in passages if p.locator.startswith("Chapter I")]
        self.assertEqual(body[0].locator, "Chapter I. Thought and Character ¶1")
        self.assertTrue(body[0].text.startswith('The aphorism, "As a man thinketh'))
        self.assertEqual(len(body), 2)  # illustration dropped
        self.assertFalse(any("must not be parsed" in p.text for p in passages))

    def test_start_marker(self):
        text = (FIX / "gutenberg_pd.txt").read_text()
        _, _, passages = gutenberg.parse_text(text, "allen", start="CHAPTER I.")
        self.assertTrue(all(p.locator.startswith("Chapter I") for p in passages))

    def test_copyrighted_ebook_rejected(self):
        with self.assertRaises(LicenceError):
            gutenberg.parse_text((FIX / "gutenberg_copyrighted.txt").read_text(), "x")

    def test_title_case_keeps_roman_numerals(self):
        self.assertEqual(gutenberg.title_case("CHAPTER IX. THE USE OF THE WILL"), "Chapter IX. The Use of the Will")

    def test_falls_back_to_mirror(self):
        calls = []

        def get(url, cache_dir, **_):
            calls.append(url)
            if "gutenberg.org" in url:
                from reborn_content.http import FetchError
                raise FetchError("403")
            return (FIX / "gutenberg_pd.txt").read_bytes()

        entry = {"id": "allen", "adapter": "gutenberg", "gutenberg_id": 4507, "mirror": "A_4507/master/4507.txt",
                 "licence": "public-domain"}
        with mock.patch("reborn_content.http.get", side_effect=get):
            res = adapters.fetch(entry, None)
        self.assertEqual(len(calls), 2)
        self.assertIn("GITenberg", res.fetched_from)


class OpenStaxTest(unittest.TestCase):
    ENTRY = {"id": "psych", "adapter": "openstax", "repo": "osbooks-psychology", "collection": "psychology-2e",
             "licence": "cc-by-4.0"}

    def test_non_commercial_licence_rejected(self):
        with fake_http({"psychology-2e.collection.xml": "openstax_nc.collection.xml"}):
            with self.assertRaises(LicenceError):
                adapters.fetch(self.ENTRY, None)

    def test_cc_by_book_is_extracted(self):
        with fake_http({"psychology-2e.collection.xml": "openstax_by.collection.xml",
                        "m1/index.cnxml": "openstax_m1.cnxml"}):
            res = adapters.fetch(self.ENTRY, None)
        self.assertEqual(res.licence, "cc-by-4.0")
        self.assertEqual(res.passages[0].locator, "Stress: What Is Stress? ¶1")
        self.assertIn("individual perceives and responds", res.passages[0].text)

    def test_licence_urls(self):
        self.assertEqual(openstax.licence_from_url("https://creativecommons.org/licenses/by/4.0/"), "cc-by-4.0")
        for bad in ["http://creativecommons.org/licenses/by-nc-sa/4.0/", "http://example.com/licence"]:
            with self.assertRaises(LicenceError):
                openstax.licence_from_url(bad)


class QuoteMatchingTest(unittest.TestCase):
    PASSAGES = [
        Passage("s", 1, "Book II ¶1", "Begin the morning by saying to thyself, I shall meet with the busybody, the ungrateful."),
        Passage("s", 2, "Book II ¶2", "Theophrastus⁠—such a comparison as one would make⁠—says it’s so. The end."),
    ]

    def test_typography_insensitive(self):
        self.assertEqual(normalise("It’s “so”—done"), normalise("It's \"so\" - done"))
        hit = find_quote("Theophrastus—such a comparison as one would make—says it's so.", self.PASSAGES)
        self.assertEqual(hit.locator, "Book II ¶2")

    def test_ellipsis_skips_words(self):
        self.assertIsNotNone(find_quote("Begin the morning … the busybody", self.PASSAGES))
        self.assertIsNotNone(find_quote("Begin the morning ... the busybody", self.PASSAGES))

    def test_altered_words_fail(self):
        self.assertIsNone(find_quote("Begin the evening by saying to thyself", self.PASSAGES))
        self.assertIsNone(find_quote("I shall meet with the busy-body", self.PASSAGES))

    def test_no_partial_words(self):
        self.assertIsNone(find_quote("egin the morning", self.PASSAGES))

    def test_across_paragraphs(self):
        self.assertIsNotNone(find_quote("the ungrateful. Theophrastus", self.PASSAGES))


VALID = {
    "source": {
        "id": "meditations-marcus-aurelius",
        "title": "Meditations",
        "authors": ["Marcus Aurelius"],
        "translator": "George Long",
        "kind": "book",
        "url": "https://standardebooks.org/ebooks/marcus-aurelius/meditations/george-long",
        "licence": "public-domain",
        "licence_url": "https://creativecommons.org/publicdomain/mark/1.0/",
        "attribution": "Marcus Aurelius, Meditations (trans. George Long), Standard Ebooks, public domain",
        "year": 180,
        "retrieved_at": "2026-10-10",
    },
    "cards": [
        {
            "id": "meditations-marcus-aurelius--01",
            "topic": "mindfulness",
            "tags": ["stoicism"],
            "title": "Expect difficult people before the day starts",
            "body": "Each morning, Marcus reminded himself that he would meet people who are rude or ungrateful. "
                    "Naming it in advance took the surprise out of it, so he could respond calmly instead of reacting.",
            "quote": "Begin the morning by saying to thyself, I shall meet with the busybody",
            "apply_it": "Before your next meeting, decide how you will respond if it goes badly.",
            "locator": "Book II ¶1",
            "quiz": {"question": "Why?", "options": ["To avoid them", "To stay calm"], "answer": 1},
        }
    ],
}


class SchemaTest(unittest.TestCase):
    def check(self, doc, name="meditations-marcus-aurelius", reg=None):
        reg = reg if reg is not None else {"meditations-marcus-aurelius": {"licence": "public-domain"}}
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / f"{name}.json").write_text(json.dumps(doc))
            report, _ = validate_library(Path(d), reg)
        return report

    def errors_for(self, mutate):
        doc = copy.deepcopy(VALID)
        mutate(doc)
        return " | ".join(self.check(doc).errors)

    def test_valid_file(self):
        r = self.check(VALID)
        self.assertEqual(r.errors, [])

    def test_rules(self):
        card = lambda d: d["cards"][0]  # noqa: E731
        cases = {
            "doesn't match file name": lambda d: d["source"].update(id="other"),
            "non-commercial": lambda d: d["source"].update(licence="cc-by-nc-sa-4.0"),
            "not one of": lambda d: card(d).update(topic="cooking"),
            "quote not allowed": lambda d: d["source"].update(licence="original-summary"),
            "health must be true": lambda d: card(d).update(topic="health"),
            "valid index": lambda d: card(d)["quiz"].update(answer=2),
            "must be 25-160": lambda d: card(d).update(body="Too short."),
            "must start with": lambda d: card(d).update(id="other-source--01"),
            "unknown card field": lambda d: card(d).update(colour="red"),
            "missing apply_it": lambda d: card(d).pop("apply_it"),
            "max 90": lambda d: card(d).update(title="x" * 91),
            "not a YYYY-MM-DD": lambda d: d["source"].update(retrieved_at="2026-13-01"),
            "lowercase slug": lambda d: card(d).update(tags=["Stoicism"]),
        }
        for expected, mutate in cases.items():
            with self.subTest(expected):
                self.assertIn(expected, self.errors_for(mutate))

    def test_duplicate_card_ids(self):
        doc = copy.deepcopy(VALID)
        dup = copy.deepcopy(doc["cards"][0])
        dup["title"] = "Another"
        doc["cards"].append(dup)
        self.assertIn("duplicate card id", " ".join(self.check(doc).errors))

    def test_source_must_be_registered_with_same_licence(self):
        self.assertIn("isn't in", " ".join(self.check(VALID, reg={}).errors))
        r = self.check(VALID, reg={"meditations-marcus-aurelius": {"licence": "cc-by-4.0"}})
        self.assertIn("differs from sources.toml", " ".join(r.errors))


class RepositoryTest(unittest.TestCase):
    """The committed registry and library are consistent."""

    def test_summary_sources_use_original_summary(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "sources.toml"
            path.write_text('[[source]]\nid = "x"\nadapter = "summary"\nurl = "https://e.com"\nlicence = "public-domain"\n')
            with self.assertRaises(registry.RegistryError):
                registry.load(path)

    def test_registry_loads(self):
        sources, candidates = registry.load(REGISTRY_PATH)
        self.assertTrue(sources)
        for c in candidates.values():
            self.assertNotIn(c["id"], sources)

    def test_library_is_valid(self):
        sources, _ = registry.load(REGISTRY_PATH)
        report, docs = validate_library(LIBRARY_DIR, sources)
        self.assertEqual(report.errors, [])
        self.assertEqual(report.warnings, [])

    def test_library_matches_json_schema(self):
        """Cross-check with the backend's JSON Schema, when it and the jsonschema package are present."""
        schema_path = LIBRARY_DIR.parent / "schema" / "library-file.schema.json"
        try:
            import jsonschema
        except ImportError:
            self.skipTest("jsonschema not installed")
        if not schema_path.exists():
            self.skipTest("content/schema/library-file.schema.json not present")
        schema = json.loads(schema_path.read_text())
        for path in sorted(LIBRARY_DIR.glob("*.json")):
            with self.subTest(path.name):
                jsonschema.validate(json.loads(path.read_text()), schema)


if __name__ == "__main__":
    unittest.main()

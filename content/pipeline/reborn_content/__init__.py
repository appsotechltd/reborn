"""Reborn content pipeline: fetch licensed source texts, validate idea cards, verify quotes."""

from pathlib import Path

PIPELINE_DIR = Path(__file__).resolve().parent.parent
CONTENT_DIR = PIPELINE_DIR.parent
LIBRARY_DIR = CONTENT_DIR / "library"
REGISTRY_PATH = PIPELINE_DIR / "sources.toml"
CACHE_DIR = CONTENT_DIR / ".cache" / "http"
BUILD_DIR = CONTENT_DIR / "build"
PASSAGES_DIR = BUILD_DIR / "passages"

"""Small cached HTTP client (stdlib only). Honours HTTPS_PROXY and the system CA store."""

from __future__ import annotations

import hashlib
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "RebornContentPipeline/0.1 (+https://github.com/appsotechltd/reborn)"


class FetchError(RuntimeError):
    pass


def get(url: str, cache_dir: Path | None, *, retries: int = 3, timeout: int = 60) -> bytes:
    """Return the body of url, reading from and writing to cache_dir when given.

    404s fail immediately; other errors are retried with exponential backoff.
    """
    path = None
    if cache_dir is not None:
        path = cache_dir / hashlib.sha256(url.encode()).hexdigest()[:40]
        if path.exists():
            return path.read_bytes()

    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise FetchError(f"{url}: 404 Not Found") from e
            last = e
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last = e
        if attempt < retries - 1:
            time.sleep(2 ** (attempt + 1))
    else:
        raise FetchError(f"{url}: {last}")

    if path is not None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
    return body


def get_first(urls: list[str], cache_dir: Path | None) -> tuple[str, bytes]:
    """Try each URL in order; return (url, body) for the first that works."""
    errors = []
    for url in urls:
        try:
            return url, get(url, cache_dir)
        except FetchError as e:
            errors.append(str(e))
    raise FetchError("all mirrors failed: " + "; ".join(errors))

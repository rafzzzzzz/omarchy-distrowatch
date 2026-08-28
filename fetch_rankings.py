#!/usr/bin/env python3
import html
import json
import os
import re
import sys
import tempfile
import time
import urllib.request


URL = "https://distrowatch.com/dwres.php?resource=popularity"
MAX_RESPONSE_BYTES = 1024 * 1024
MAX_RANKINGS = 20


def parse_rankings(document):
    start = document.find("Last 6 months")
    end = document.find("Last 3 months", start + 1)
    if start < 0 or end < 0:
        raise ValueError("six-month ranking table not found")

    section = document[start:end]
    row_pattern = re.compile(
        r'<th class="phr1">\s*(\d+)\s*</th>\s*'
        r'<td class="phr2"><a[^>]+href="([^"]+)"[^>]*>(.*?)</a></td>\s*'
        r'<td class="phr3"[^>]*>\s*([\d,]+)\s*'
        r'<img[^>]+/(aup|adown|alevel)\.png',
        re.DOTALL,
    )

    rankings = []
    trend_names = {"aup": "up", "adown": "down", "alevel": "level"}
    for match in row_pattern.finditer(section):
        rank, href, raw_name, hits, trend = match.groups()
        name = html.unescape(re.sub(r"<[^>]+>", "", raw_name)).strip()
        slug_match = re.fullmatch(r"/?([a-zA-Z0-9_-]+)", html.unescape(href))
        if not name or not slug_match:
            continue
        rankings.append(
            {
                "rank": int(rank),
                "name": name[:80],
                "hpd": int(hits.replace(",", "")),
                "trend": trend_names[trend],
                "url": "https://distrowatch.com/" + slug_match.group(1),
            }
        )
        if len(rankings) >= MAX_RANKINGS:
            break

    if len(rankings) < MAX_RANKINGS:
        raise ValueError("ranking table was incomplete")
    return rankings


def fetch_rankings():
    request = urllib.request.Request(
        URL,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read(MAX_RESPONSE_BYTES + 1)
    if len(body) > MAX_RESPONSE_BYTES:
        raise ValueError("response exceeded size limit")
    return parse_rankings(body.decode("utf-8", errors="replace"))


def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as cache_file:
            cached = json.load(cache_file)
        if isinstance(cached.get("rankings"), list) and cached["rankings"]:
            return cached
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return None


def write_cache(path, payload):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary_path = tempfile.mkstemp(prefix="distrowatch.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as cache_file:
            json.dump(payload, cache_file, separators=(",", ":"))
            cache_file.write("\n")
        os.replace(temporary_path, path)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def get_payload(cache_path):
    try:
        payload = {
            "rankings": fetch_rankings(),
            "updatedAt": int(time.time()),
            "stale": False,
            "error": "",
        }
        if cache_path != os.devnull:
            write_cache(cache_path, payload)
    except Exception as error:
        payload = load_cache(cache_path) or {"rankings": [], "updatedAt": 0}
        payload["stale"] = True
        payload["error"] = str(error)[:160]
    return payload


def main():
    cache_path = sys.argv[1] if len(sys.argv) > 1 else os.devnull
    payload = get_payload(cache_path)
    print(json.dumps(payload, separators=(",", ":")))


if __name__ == "__main__":
    main()

"""
Download a curated set of OFL handwriting fonts from the Google Fonts GitHub
repo into ml/data/fonts/. Reproducible, license-clean bootstrap for the
synthetic handwritten-move generator.

Uses the GitHub contents API to resolve each family's actual .ttf filename
(handles both static "-Regular.ttf" and variable "Family[wght].ttf" naming),
so no fragile hard-coded URLs.

Files are saved as "<ofl-dir>__<original>.ttf" so synth_generator can derive a
stable font id (the ofl-dir prefix) for held-out splits.

Usage:
    python ml/data/fetch_fonts.py --out ml/data/fonts
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Optional

# Curated handwriting families (ofl directory names = lowercase, no spaces).
# A deliberate mix of Latin and non-Latin scripts: the non-Latin ones (Korean/
# Thai/Japanese origin) often lack the Turkish "Ş" glyph and are auto-excluded
# from TR generation by synth_generator's glyph filter — they still add EN style
# diversity.
FONT_DIRS: List[str] = [
    "caveat", "patrickhand", "architectsdaughter", "indieflower", "kalam",
    "reeniebeanie", "shadowsintolight", "shadowsintolighttwo", "gloriahallelujah",
    "rocksalt", "permanentmarker", "homemadeapple", "comingsoon", "justanotherhand",
    "coveredbyyourgrace", "schoolbell", "walterturncoat", "cabinsketch", "gochihand",
    "neucha", "sriracha", "caveatbrush", "mali", "kleeone", "nanumpenscript",
    "delius", "itim", "gaegu",
]

# Families live under different license dirs in google/fonts. Try OFL first,
# then Apache-2.0 (both are fine to bundle). Several classic handwriting fonts
# (Permanent Marker, Rock Salt, Homemade Apple, ...) are Apache-licensed.
LICENSE_DIRS = ("ofl", "apache")
API = "https://api.github.com/repos/google/fonts/contents/{lic}/{d}"
HEADERS = {"User-Agent": "arbiter-ai-fetch-fonts", "Accept": "application/vnd.github+json"}


def _get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _pick_ttf(items: list) -> Optional[dict]:
    """Choose the best .ttf from a directory listing (prefer Regular static)."""
    ttfs = [it for it in items if it.get("name", "").lower().endswith(".ttf")]
    if not ttfs:
        return None
    for it in ttfs:
        if it["name"].lower().endswith("-regular.ttf"):
            return it
    # Variable font (e.g. Caveat[wght].ttf) or any single weight.
    return ttfs[0]


def fetch_family(ofl_dir: str, out_dir: Path) -> Optional[Path]:
    items = None
    for lic in LICENSE_DIRS:
        try:
            items = json.loads(_get(API.format(lic=lic, d=ofl_dir)))
            break
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                continue  # try the next license dir
            print(f"  [skip] {ofl_dir}: HTTP {exc.code}")
            return None
        except Exception as exc:  # noqa: BLE001
            print(f"  [skip] {ofl_dir}: {exc}")
            return None

    if not isinstance(items, list):
        print(f"  [skip] {ofl_dir}: not found in any license dir")
        return None

    chosen = _pick_ttf(items)
    if chosen is None:
        print(f"  [skip] {ofl_dir}: no .ttf found")
        return None

    dest = out_dir / f"{ofl_dir}__{chosen['name']}"
    if dest.exists():
        print(f"  [have] {dest.name}")
        return dest

    try:
        data = _get(chosen["download_url"], timeout=60)
    except Exception as exc:  # noqa: BLE001
        print(f"  [skip] {ofl_dir}: download failed ({exc})")
        return None

    dest.write_bytes(data)
    print(f"  [ok]   {dest.name} ({len(data) // 1024} KB)")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser(description="Fetch OFL handwriting fonts")
    ap.add_argument("--out", default="ml/data/fonts")
    ap.add_argument("--delay", type=float, default=0.3,
                    help="seconds between requests (be gentle to the GitHub API)")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {len(FONT_DIRS)} families into {out_dir} …")
    ok = 0
    for d in FONT_DIRS:
        if fetch_family(d, out_dir) is not None:
            ok += 1
        time.sleep(args.delay)

    print(f"\n[done] {ok}/{len(FONT_DIRS)} fonts available in {out_dir}")
    print("Next: python ml/data/synth_generator.py --n 20000 --locales tr en")


if __name__ == "__main__":
    main()

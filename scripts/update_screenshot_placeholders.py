#!/usr/bin/env python3
"""Replace `[SCREENSHOT: ...]` placeholders with actual image links.

Usage:
    python scripts/update_screenshot_placeholders.py

The script scans all Markdown files under `docs/`, looks for
`[SCREENSHOT: description]` placeholders, slugifies the description, and if a
matching file exists in `docs/screenshots/`, replaces the placeholder with a
Markdown image link (`![description](relative/path.png)`).
"""
import argparse
import os
import pathlib
import re
from typing import Dict

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS_DIR = ROOT / "docs"
SCREENSHOT_DIR = DOCS_DIR / "screenshots"
PLACEHOLDER_PATTERN = re.compile(r"\[SCREENSHOT:\s*([^\]]+)\]")


def slugify(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def build_screenshot_index() -> Dict[str, pathlib.Path]:
    index: Dict[str, pathlib.Path] = {}
    if not SCREENSHOT_DIR.exists():
        return index
    for path in SCREENSHOT_DIR.iterdir():
        if path.is_file():
            index.setdefault(slugify(path.stem), path)
    return index


def replace_placeholders(index: Dict[str, pathlib.Path], dry_run: bool) -> int:
    updated_files = 0
    for md_file in sorted(DOCS_DIR.rglob("*.md")):
        text = md_file.read_text()
        changed = [False]

        def repl(match: re.Match[str]) -> str:
            description = match.group(1).strip()
            slug = slugify(description)
            screenshot = index.get(slug)
            if screenshot is None:
                return match.group(0)
            rel_path = os.path.relpath(screenshot, md_file.parent).replace("\\", "/")
            changed[0] = True
            return f"![{description}]({rel_path})"

        new_text = PLACEHOLDER_PATTERN.sub(repl, text)
        if changed[0]:
            updated_files += 1
            if not dry_run:
                md_file.write_text(new_text)
            print(f"Updated {md_file.relative_to(ROOT)}")
    return updated_files


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and report replacements without modifying files.",
    )
    args = parser.parse_args()

    index = build_screenshot_index()
    if not index:
        print(f"No screenshots found in {SCREENSHOT_DIR}")
        return

    count = replace_placeholders(index, args.dry_run)
    if count == 0:
        print("No placeholders replaced.")
    else:
        print(f"Replaced placeholders in {count} file(s).{' (dry run)' if args.dry_run else ''}")


if __name__ == "__main__":
    main()

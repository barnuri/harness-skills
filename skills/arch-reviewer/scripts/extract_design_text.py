#!/usr/bin/env python3
"""Collect the text of a design from files or folders (.md, .docx, .html) for review.

A design written by the arch-design skill usually sits as design.md + design.html (+ design.docx)
in one folder. The markdown is the source of truth, so a sibling .html or .docx with the same stem
contributes only its reviewer comments, not a second copy of the text.

Usage:
    python3 extract_design_text.py <file-or-folder> [...] [--inventory]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import ClassVar

sys.path.insert(0, str(Path(__file__).resolve().parent))

from docx_text_reader import DocxTextReader
from html_text_parser import HtmlTextParser


class DesignTextExtractor:
    _SUFFIX_FORMATS: ClassVar[dict[str, str]] = {
        ".md": "md",
        ".markdown": "md",
        ".docx": "docx",
        ".html": "html",
        ".htm": "html",
    }
    _SOURCE_PRIORITY = ("md", "docx", "html")
    _EMBEDDED_COMMENTS = re.compile(
        r'<script[^>]*id="design-comments"[^>]*>(.*?)</script>', re.DOTALL
    )
    _ARCH_DESIGN_MARKERS = (
        "arch-design` skill",
        "arch-design skill",
        'id="design-comments"',
    )
    _SKIPPED_DIRS: ClassVar[set[str]] = {
        "node_modules",
        ".git",
        ".venv",
        "__pycache__",
        ".mermaid-check",
    }

    def __init__(self) -> None:
        self._docx_reader = DocxTextReader()

    def collect(self, inputs: list[Path]) -> list[Path]:
        files: list[Path] = []
        for item in inputs:
            if item.is_dir():
                files.extend(self._walk(item))
            elif item.is_file() and item.suffix.lower() in self._SUFFIX_FORMATS:
                files.append(item)
            elif item.is_file():
                raise ValueError(
                    f"unsupported file type: {item} (use .md, .docx or .html)"
                )
            else:
                raise ValueError(f"no such file or folder: {item}")
        return sorted(dict.fromkeys(path.resolve() for path in files))

    def render(self, files: list[Path], inventory_only: bool) -> str:
        entries = [self._entry(path, files) for path in files]
        lines = [
            "# Design input",
            "",
            "| File | Format | Role | Origin | Characters | Comments |",
            "|---|---|---|---|---|---|",
        ]
        for entry in entries:
            lines.append(
                f"| `{entry['path']}` | {entry['format']} | {entry['role']} | {entry['origin']} "
                f"| {len(entry['text'])} | {len(entry['comments'])} |"
            )
        if inventory_only:
            return "\n".join(lines) + "\n"
        for entry in entries:
            lines.extend(self._section(entry))
        return "\n".join(lines).rstrip() + "\n"

    def _walk(self, folder: Path) -> list[Path]:
        return [
            path
            for path in folder.rglob("*")
            if path.is_file()
            and path.suffix.lower() in self._SUFFIX_FORMATS
            and not any(
                part.startswith(".") or part in self._SKIPPED_DIRS
                for part in path.relative_to(folder).parts
            )
        ]

    def _entry(self, path: Path, files: list[Path]) -> dict:
        file_format = self._SUFFIX_FORMATS[path.suffix.lower()]
        raw_html = (
            path.read_text(encoding="utf-8", errors="replace")
            if file_format == "html"
            else ""
        )
        text, comments = self._read(path, file_format, raw_html)
        is_source = self._is_source(path, file_format, files)
        return {
            "path": path,
            "format": file_format,
            "role": "source" if is_source else "comments only",
            "origin": "arch-design"
            if self._is_arch_design(text, raw_html)
            else "generic",
            "text": text if is_source else "",
            "comments": comments,
        }

    def _read(
        self, path: Path, file_format: str, raw_html: str
    ) -> tuple[str, list[dict]]:
        if file_format == "docx":
            return self._docx_reader.read(path)
        if file_format == "html":
            parser = HtmlTextParser()
            parser.feed(raw_html)
            return parser.text(), self._embedded_comments(raw_html)
        return path.read_text(encoding="utf-8", errors="replace"), []

    def _is_source(self, path: Path, file_format: str, files: list[Path]) -> bool:
        siblings = {
            self._SUFFIX_FORMATS[other.suffix.lower()]
            for other in files
            if other.parent == path.parent and other.stem == path.stem and other != path
        }
        rank = self._SOURCE_PRIORITY.index(file_format)
        return not any(self._SOURCE_PRIORITY.index(other) < rank for other in siblings)

    def _is_arch_design(self, text: str, raw_html: str) -> bool:
        haystack = text + raw_html
        return any(marker in haystack for marker in self._ARCH_DESIGN_MARKERS)

    def _embedded_comments(self, raw_html: str) -> list[dict]:
        match = self._EMBEDDED_COMMENTS.search(raw_html)
        if not match:
            return []
        try:
            parsed = json.loads(match.group(1).replace("<\\/", "</") or "[]")
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []

    def _section(self, entry: dict) -> list[str]:
        lines = [
            "",
            "---",
            "",
            f"## File: `{entry['path']}` ({entry['format']}, {entry['role']})",
            "",
        ]
        if entry["text"]:
            lines.append(entry["text"].rstrip())
        if entry["comments"]:
            lines.extend(["", f"### Reviewer comments in `{entry['path'].name}`", ""])
            lines.extend(self._comment_line(comment) for comment in entry["comments"])
        return lines

    def _comment_line(self, comment: dict) -> str:
        anchor = comment.get("anchor") or {}
        where = f" `#{anchor['section']}`" if anchor.get("section") else ""
        quote = (
            f' on "{" ".join(anchor["quote"].split())}"' if anchor.get("quote") else ""
        )
        status = comment.get("status") or "open"
        return f"- **{comment.get('author') or 'Anonymous'}** ({status}){where}{quote}: {comment.get('body') or ''}"

    @staticmethod
    def main() -> int:
        parser = argparse.ArgumentParser(
            description="Collect design text for an architecture review"
        )
        parser.add_argument(
            "inputs", nargs="+", type=Path, help="design files or folders"
        )
        parser.add_argument(
            "--inventory",
            action="store_true",
            help="print only the file table, not the text",
        )
        args = parser.parse_args()

        extractor = DesignTextExtractor()
        try:
            files = extractor.collect(args.inputs)
            if not files:
                print("error: no .md, .docx or .html files found", file=sys.stderr)
                return 1
            print(extractor.render(files, args.inventory), end="")
        except ValueError as err:
            print(f"error: {err}", file=sys.stderr)
            return 1
        return 0


if __name__ == "__main__":
    sys.exit(DesignTextExtractor.main())

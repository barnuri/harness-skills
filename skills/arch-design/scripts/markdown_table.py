#!/usr/bin/env python3
"""Shared markdown pipe-table helpers for both design renderers.

Row splitting and divider detection were duplicated across the HTML and docx renderers; a fix in
one silently left the other behind. One copy now.
"""

from __future__ import annotations

import re


class MarkdownTable:
    """Recognises and splits GitHub-style pipe tables."""

    DIVIDER = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")

    def is_divider(self, line: str) -> bool:
        return bool(self.DIVIDER.match(line))

    def starts_at(self, lines: list[str], index: int) -> bool:
        """A table needs a header row followed by a divider row."""
        if "|" not in lines[index]:
            return False
        return index + 1 < len(lines) and self.is_divider(lines[index + 1])

    def split_row(self, line: str) -> list[str]:
        stripped = line.strip()
        if stripped.startswith("|"):
            stripped = stripped[1:]
        if stripped.endswith("|"):
            stripped = stripped[:-1]
        return [cell.strip() for cell in stripped.split("|")]

    def body_end(self, lines: list[str], start: int) -> int:
        """Index just past the last body row of the table whose header is at `start`."""
        end = start + 2
        while end < len(lines) and "|" in lines[end] and lines[end].strip():
            end += 1
        return end

    def pad(self, row: list[str], width: int) -> list[str]:
        return (row + [""] * width)[:width]

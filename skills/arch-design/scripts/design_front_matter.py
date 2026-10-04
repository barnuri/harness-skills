#!/usr/bin/env python3
"""Shared YAML front-matter handling for both design renderers.

Extracted because the HTML and docx renderers each carried a copy, and both copies closed the
block with `find("\\n---")` — a prefix match that also fires on `----`, consuming four characters
and leaking the remaining dashes into the document body. Closing on a full line fixes it once.
"""

from __future__ import annotations

import re


class DesignFrontMatter:
    """Splits a design document into its front-matter fields and its body."""

    _OPENING_FENCE = "---"
    _CLOSING_FENCE = re.compile(r"^---\s*$")
    _TRAILING_COMMENT = re.compile(r"\s{2,}#.*$")

    def split(self, text: str) -> tuple[dict[str, str], str]:
        normalized = text.replace("\r\n", "\n")
        lines = normalized.split("\n")
        if not lines or lines[0].strip() != self._OPENING_FENCE:
            return {}, normalized

        for index in range(1, len(lines)):
            if self._CLOSING_FENCE.match(lines[index]):
                fields = self._parse(lines[1:index])
                body = "\n".join(lines[index + 1 :]).lstrip("\n")
                return fields, body

        # Unterminated front matter: treat the whole document as body rather than silently
        # swallowing it.
        return {}, normalized

    def _parse(self, lines: list[str]) -> dict[str, str]:
        """Minimal flat key/value YAML — the only shape the template uses."""
        fields: dict[str, str] = {}
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or ":" not in line:
                continue
            key, _, value = line.partition(":")
            value = self._TRAILING_COMMENT.sub("", value).strip().strip("'\"")
            if value:
                fields[key.strip().lower()] = value
        return fields

#!/usr/bin/env python3
"""Sanitizes the inline HTML that survives into a rendered design document.

`design.html` is emailed to product and R&D and opened in a browser, and design documents absorb
pasted content from tickets, wikis, and other people's drafts. The renderer lets a short allowlist
of inline tags through so the SELECTED/DECISION badge markup keeps working; without this pass it
also lets through `onclick=`, `javascript:` hrefs, and arbitrary `style`.

Stdlib only, by constraint — the HTML path must never require an install.
"""

from __future__ import annotations

import html
import re


class HtmlSanitizer:
    """Strips event handlers and unsafe URLs from allowlisted inline HTML."""

    ALLOWED_TAGS = (
        "strong|ins|em|code|br|span|sub|sup|a|b|i|u|kbd|del|mark|small|abbr|cite|q"
    )
    TAG = re.compile(rf"</?(?:{ALLOWED_TAGS})\b(?:\s[^<>]*)?/?>", re.IGNORECASE)

    _TAG_PARTS = re.compile(r"^</?\s*([A-Za-z][A-Za-z0-9]*)((?:\s[^<>]*)?)(/?)>$", re.DOTALL)
    _ATTRIBUTE = re.compile(r"""([A-Za-z_:][-\w:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s"'<>`]+)""")
    _SAFE_SCHEME = re.compile(r"^(?:https?:|mailto:|#|/|\./|\.\./)", re.IGNORECASE)
    _SCHEME_LIKE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
    # The badge markup is the only reason `style` is allowed at all; keep it to plain colours.
    _SAFE_STYLE = re.compile(r"^\s*color\s*:\s*(#[0-9A-Fa-f]{3,8}|[A-Za-z]+)\s*;?\s*$")
    _URL_ATTRIBUTES = {"href", "src", "xlink:href"}
    _KEEPABLE = {"href", "title", "class", "style", "lang", "dir", "cite", "datetime"}

    def clean_tag(self, tag: str) -> str:
        """Rebuild one allowlisted tag, dropping anything that can execute or navigate unsafely."""
        parts = self._TAG_PARTS.match(tag)
        if not parts:
            return html.escape(tag, quote=False)
        name, raw_attributes, self_closing = parts.group(1), parts.group(2), parts.group(3)
        if tag.startswith("</"):
            return f"</{name.lower()}>"
        if not self._is_attribute_list(raw_attributes):
            # Prose, not markup: the template is full of <angle-bracket> prompts and some of them
            # open with an allowlisted tag name — "<A concrete example — …>" would otherwise become
            # a bare unclosed <a> that swallows the rest of the document.
            return html.escape(tag, quote=False)

        kept = [
            f'{attribute}="{html.escape(value, quote=True)}"'
            for attribute, value in self._safe_attributes(raw_attributes)
        ]
        rendered = " ".join([name.lower()] + kept)
        return f"<{rendered}{' /' if self_closing else ''}>"

    def _is_attribute_list(self, raw: str) -> bool:
        """True when the text after the tag name is entirely well-formed attributes (or empty)."""
        remainder = self._ATTRIBUTE.sub("", raw or "")
        remainder = re.sub(r"\b[A-Za-z_:][-\w:.]*\b", "", remainder)  # bare boolean attributes
        return not remainder.strip()

    def _safe_attributes(self, raw: str) -> list[tuple[str, str]]:
        safe: list[tuple[str, str]] = []
        for match in self._ATTRIBUTE.finditer(raw or ""):
            attribute = match.group(1).lower()
            value = match.group(2).strip("\"'")
            if attribute.startswith("on") or attribute not in self._KEEPABLE:
                continue
            if attribute in self._URL_ATTRIBUTES and not self.is_safe_url(value):
                continue
            if attribute == "style" and not self._SAFE_STYLE.match(value):
                continue
            safe.append((attribute, value))
        return safe

    def is_safe_url(self, url: str) -> bool:
        """Allow http(s), mailto, fragments and relative paths; reject javascript:, data:, vbscript:."""
        candidate = html.unescape(url).strip()
        # Control characters and whitespace are used to smuggle `java\tscript:` past naive checks.
        candidate = re.sub(r"[\x00-\x20\x7f]", "", candidate)
        if not candidate:
            return False
        if self._SAFE_SCHEME.match(candidate):
            return True
        # No scheme at all means a relative reference, which is safe.
        return not self._SCHEME_LIKE.match(candidate)

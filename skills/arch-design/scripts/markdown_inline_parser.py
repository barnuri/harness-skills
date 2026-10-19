#!/usr/bin/env python3
"""Inline-span markdown parsing for the arch-design HTML renderer.

Stdlib only by design: the rendered artifact must be produceable with no `pip install`, so the
supported syntax is deliberately limited to the subset `references/template.md` emits.
"""

from __future__ import annotations

import base64
import html
import re
from pathlib import Path

from html_sanitizer import HtmlSanitizer


class MarkdownInlineParser:
    """Converts inline markdown spans to HTML.

    Code spans, allowlisted raw HTML, and LaTeX decision badges are extracted to placeholders
    before escaping so their contents are never re-parsed or double-escaped, then restored at the
    end. Everything that passes through as real HTML goes through the sanitizer first — the
    rendered file is opened in a browser by people who did not write it.
    """

    INLINE_TAGS = HtmlSanitizer.ALLOWED_TAGS

    # Sentinel cannot be produced by the escaping stage and cannot appear in the source, because
    # any literal occurrence is stripped before parking begins.
    _SENTINEL = "\ue000"  # Private Use Area; stripped from input before parking
    _PLACEHOLDER_PATTERN = re.compile(rf"{_SENTINEL}(\d+){_SENTINEL}")

    _CODE_SPAN = re.compile(r"`([^`]+)`")
    # Allowlist, not a general tag match: the template is full of <angle-bracket> placeholder
    # prompts, and a permissive pattern swallows them as unknown elements so they render blank.
    _RAW_HTML = HtmlSanitizer.TAG
    # $\color{green}\textbf{SELECTED}$ — the GitHub-compatible decision badge.
    _LATEX_BADGE = re.compile(r"\$\\color\{(\w+)\}\\textbf\{([^}]*)\}\$")
    _LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
    _IMAGE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)")
    _IMAGE_TYPES = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
        ".svg": "image/svg+xml",
    }
    _BOLD = re.compile(r"\*\*(.+?)\*\*")
    _ITALIC_STAR = re.compile(r"(?<!\*)\*([^*\n]+?)\*(?!\*)")
    _ITALIC_UNDERSCORE = re.compile(r"(?<![\w\\])_([^_\n]+?)_(?![\w])")

    def __init__(self, base_dir: Path | None = None) -> None:
        self._base_dir = base_dir.resolve() if base_dir else None
        self._sanitizer = HtmlSanitizer()
        self._parked: list[str] = []

    def to_html(self, text: str) -> str:
        self._parked = []
        parked = self._park_verbatim(text.replace(self._SENTINEL, ""))
        escaped = html.escape(parked, quote=False)
        styled = self._apply_emphasis(escaped)
        return self._restore(styled)

    def _park_verbatim(self, text: str) -> str:
        """Replace spans whose contents must not be escaped or re-parsed with placeholders."""
        text = self._CODE_SPAN.sub(
            lambda m: self._park(f"<code>{html.escape(m.group(1), quote=False)}</code>"), text
        )
        text = self._IMAGE.sub(lambda m: self._park(self._render_image(m.group(1), m.group(2))), text)
        text = self._LATEX_BADGE.sub(
            lambda m: self._park(
                f'<span class="badge">{html.escape(m.group(2), quote=False)}</span>'
            ),
            text,
        )
        return self._RAW_HTML.sub(
            lambda m: self._park(self._sanitizer.clean_tag(m.group(0))), text
        )

    def _park(self, rendered: str) -> str:
        self._parked.append(rendered)
        return f"{self._SENTINEL}{len(self._parked) - 1}{self._SENTINEL}"

    def _apply_emphasis(self, text: str) -> str:
        text = self._LINK.sub(self._render_link, text)
        text = self._BOLD.sub(r"<strong>\1</strong>", text)
        text = self._ITALIC_STAR.sub(r"<em>\1</em>", text)
        return self._ITALIC_UNDERSCORE.sub(r"<em>\1</em>", text)

    def _render_link(self, match: re.Match[str]) -> str:
        label, url = match.group(1), match.group(2)
        if not self._sanitizer.is_safe_url(url):
            # Keep the text visible rather than silently dropping it, but never make it clickable.
            return f"{label} ({html.escape(url, quote=False)})"
        return f'<a href="{html.escape(url, quote=True)}">{label}</a>'

    def _render_image(self, alt: str, src: str) -> str:
        data_uri = self._inline_image(src)
        if data_uri:
            return f'<img src="{data_uri}" alt="{html.escape(alt, quote=True)}">'
        label = html.escape(alt or src, quote=False)
        if self._sanitizer.is_safe_url(src):
            return f'<a href="{html.escape(src, quote=True)}">{label}</a>'
        return label

    def _inline_image(self, src: str) -> str | None:
        """Embed a local image as a data URI, so the rendered file still opens with no network."""
        if self._base_dir is None or not self._sanitizer.is_safe_url(src) or ":" in src:
            return None
        path = (self._base_dir / src).resolve()
        mime = self._IMAGE_TYPES.get(path.suffix.lower())
        if not mime or not path.is_relative_to(self._base_dir) or not path.is_file():
            return None
        return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"

    def _restore(self, text: str) -> str:
        return self._PLACEHOLDER_PATTERN.sub(
            lambda m: self._parked[int(m.group(1))]
            if int(m.group(1)) < len(self._parked)
            else "",
            text,
        )

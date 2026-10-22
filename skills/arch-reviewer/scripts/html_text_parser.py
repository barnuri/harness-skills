from __future__ import annotations

from html.parser import HTMLParser
from typing import ClassVar


class HtmlTextParser(HTMLParser):
    """Turns an HTML page into Markdown-ish text: headings keep their level, table cells keep
    their row, and script, style and the review-layer UI are dropped."""

    _SKIPPED_TAGS: ClassVar[set[str]] = {
        "script",
        "style",
        "noscript",
        "template",
        "svg",
        "head",
    }
    _SKIPPED_CLASS_PREFIXES = ("anno-", "toc")
    _VOID_TAGS: ClassVar[set[str]] = {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "source",
        "track",
        "wbr",
    }
    _BLOCK_TAGS: ClassVar[set[str]] = {
        "p",
        "div",
        "section",
        "article",
        "li",
        "tr",
        "br",
        "pre",
        "blockquote",
        "details",
        "summary",
        "figure",
        "dt",
        "dd",
    }
    _HEADING_LEVELS: ClassVar[dict[str, int]] = {
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "h5": 5,
        "h6": 6,
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip_stack: list[str] = []
        self._parts: list[str] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self._skip_stack or self._is_skipped(tag, attrs):
            if tag not in self._VOID_TAGS:
                self._skip_stack.append(tag)
            return
        if tag in self._HEADING_LEVELS:
            self._parts.append("\n\n" + "#" * self._HEADING_LEVELS[tag] + " ")
        elif tag == "tr":
            self._row = []
        elif tag in ("td", "th"):
            self._cell = []
        elif tag == "li":
            self._parts.append("\n- ")
        elif tag in self._BLOCK_TAGS:
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self._skip_stack:
            while tag in self._skip_stack and self._skip_stack.pop() != tag:
                pass
            return
        if tag in ("td", "th") and self._row is not None and self._cell is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self._parts.append("\n| " + " | ".join(self._row) + " |")
            self._row = None
        elif tag in self._HEADING_LEVELS or tag in self._BLOCK_TAGS:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_stack:
            return
        if self._cell is not None:
            self._cell.append(data)
            return
        self._parts.append(data)

    def text(self) -> str:
        lines = [" ".join(line.split()) for line in "".join(self._parts).splitlines()]
        collapsed: list[str] = []
        for line in lines:
            if line or (collapsed and collapsed[-1]):
                collapsed.append(line)
        return "\n".join(collapsed).strip() + "\n"

    def _is_skipped(self, tag: str, attrs: list[tuple[str, str | None]]) -> bool:
        if tag in self._SKIPPED_TAGS:
            return True
        classes = (dict(attrs).get("class") or "").split()
        return any(name.startswith(self._SKIPPED_CLASS_PREFIXES) for name in classes)

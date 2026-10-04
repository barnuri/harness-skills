#!/usr/bin/env python3
"""Block-level markdown parsing for the arch-design HTML renderer.

Handles the block constructs `references/template.md` emits: ATX headings, fenced code (including
```mermaid), tables, ordered/unordered lists with nesting, blockquotes, horizontal rules, and
paragraphs. Lines beginning `Q:` become highlighted open-question callouts so reviewers cannot
miss an unresolved decision.
"""

from __future__ import annotations

import html
import re

from markdown_inline_parser import MarkdownInlineParser
from markdown_table import MarkdownTable


class MarkdownBlockParser:
    """Converts a markdown document body into HTML, collecting headings for the table of contents."""

    _HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
    _FENCE = re.compile(r"^```\s*([A-Za-z0-9_-]*)\s*$")
    _HRULE = re.compile(r"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$")
    _LIST_ITEM = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
    # `Q:` auto-numbers. `Q3:` keeps the author's number, because prose, review comments and
    # downstream tasks cite questions by name and silent renumbering would break those references.
    _QUESTION = re.compile(r"^Q(\d*)[:.]\s*(.*)$")
    _SLUG_STRIP = re.compile(r"[^a-z0-9\s-]")
    _INDENT_PER_LEVEL = 2

    def __init__(self) -> None:
        self._inline = MarkdownInlineParser()
        self._table = MarkdownTable()
        self.headings: list[tuple[int, str, str]] = []
        self.questions: list[tuple[str, str, str]] = []
        self._question_anchors: set[str] = set()
        self.has_mermaid = False
        self.mermaid_blocks: list[str] = []
        self._slugs: set[str] = set()

    def to_html(self, body: str) -> str:
        self.headings = []
        self.questions = []
        self._question_anchors = set()
        self.has_mermaid = False
        self.mermaid_blocks: list[str] = []
        self._slugs = set()
        lines = body.replace("\r\n", "\n").split("\n")
        return "\n".join(self._consume(lines))

    def _consume(self, lines: list[str]) -> list[str]:
        out: list[str] = []
        index = 0
        while index < len(lines):
            line = lines[index]
            if not line.strip():
                index += 1
                continue
            for handler in (
                self._take_fence,
                self._take_heading,
                self._take_hrule,
                self._take_table,
                self._take_list,
                self._take_blockquote,
            ):
                consumed = handler(lines, index, out)
                if consumed:
                    index += consumed
                    break
            else:
                index += self._take_paragraph(lines, index, out)
        return out

    # --- block handlers ---------------------------------------------------
    # Each returns the number of lines consumed, or 0 if the block does not apply.

    def _take_fence(self, lines: list[str], start: int, out: list[str]) -> int:
        opening = self._FENCE.match(lines[start])
        if not opening:
            return 0
        language = opening.group(1)
        end = start + 1
        while end < len(lines) and not self._FENCE.match(lines[end]):
            end += 1
        content = "\n".join(lines[start + 1 : end])
        if language == "mermaid":
            self.has_mermaid = True
            self.mermaid_blocks.append(content)
            out.append(f'<div class="mermaid">{html.escape(content, quote=False)}</div>')
        else:
            class_attr = f' class="language-{language}"' if language else ""
            out.append(
                f"<pre><code{class_attr}>{html.escape(content, quote=False)}</code></pre>"
            )
        # +1 for the opening fence, +1 for the closing fence when it was found.
        return (end - start) + (1 if end < len(lines) else 0)

    def _take_heading(self, lines: list[str], start: int, out: list[str]) -> int:
        match = self._HEADING.match(lines[start])
        if not match:
            return 0
        level = len(match.group(1))
        text = match.group(2).strip()
        anchor = self._unique_slug(text)
        self.headings.append((level, text, anchor))
        out.append(f'<h{level} id="{anchor}">{self._inline.to_html(text)}</h{level}>')
        return 1

    def _take_hrule(self, lines: list[str], start: int, out: list[str]) -> int:
        if not self._HRULE.match(lines[start]):
            return 0
        out.append("<hr>")
        return 1

    def _take_table(self, lines: list[str], start: int, out: list[str]) -> int:
        if not self._table.starts_at(lines, start):
            return 0
        header = self._table.split_row(lines[start])
        end = self._table.body_end(lines, start)
        if not any(cell for cell in header):
            # Layout table with no header text: the metadata bar built from front matter already
            # carries these fields, so rendering it again shows an empty header band.
            return end - start
        body_rows = [self._table.split_row(line) for line in lines[start + 2 : end]]
        out.append(self._render_table(header, body_rows))
        return end - start

    def _take_list(self, lines: list[str], start: int, out: list[str]) -> int:
        if not self._LIST_ITEM.match(lines[start]):
            return 0
        items: list[list[str]] = []
        end = start
        while end < len(lines):
            match = self._LIST_ITEM.match(lines[end])
            if match:
                items.append(list(match.groups()))
                end += 1
                continue
            # Lazy continuation: a wrapped bullet keeps going on the next line. Without this the
            # list closes and the remainder renders as a full-width paragraph outside the <li>.
            if items and lines[end].strip() and not self._starts_new_block(lines, end):
                items[-1][2] += " " + lines[end].strip()
                end += 1
                continue
            break
        items = [tuple(item) for item in items]
        # Start at the first item's own indent: a run whose first line is already indented used to
        # be rendered at depth 0, and the nested-splice below then corrupted the enclosing tag.
        base_depth = len(items[0][0]) // self._INDENT_PER_LEVEL
        out.append(self._render_list(items, 0, base_depth)[0])
        return end - start

    def _take_blockquote(self, lines: list[str], start: int, out: list[str]) -> int:
        if not lines[start].lstrip().startswith(">"):
            return 0
        end = start
        collected: list[str] = []
        while end < len(lines) and lines[end].lstrip().startswith(">"):
            collected.append(lines[end].lstrip()[1:].lstrip())
            end += 1
        inner = "\n".join(self._consume(collected))
        out.append(f"<blockquote>{inner}</blockquote>")
        return end - start

    def _take_paragraph(self, lines: list[str], start: int, out: list[str]) -> int:
        end = start
        collected: list[str] = []
        while end < len(lines) and lines[end].strip() and not self._starts_new_block(lines, end):
            collected.append(lines[end].strip())
            end += 1
        if not collected:
            return 1
        text = " ".join(collected)
        question = self._QUESTION.match(text)
        if question:
            rendered = self._inline.to_html(question.group(2))
            number = question.group(1) or str(len(self.questions) + 1)
            anchor = f"q-{number}"
            while anchor in self._question_anchors:
                anchor += "x"
            self._question_anchors.add(anchor)
            section = self.headings[-1][2] if self.headings else ""
            self.questions.append((anchor, section, question.group(2)))
            out.append(
                f'<p class="open-question" id="{anchor}" data-question="{number}" '
                f'data-section="{section}">'
                f'<span class="q-label">Q{number}</span> {rendered}</p>'
            )
        else:
            out.append(f"<p>{self._inline.to_html(text)}</p>")
        return end - start

    def _starts_new_block(self, lines: list[str], index: int) -> bool:
        if index == 0:
            return False
        line = lines[index]
        return bool(
            self._HEADING.match(line)
            or self._FENCE.match(line)
            or self._HRULE.match(line)
            or self._LIST_ITEM.match(line)
            or line.lstrip().startswith(">")
            or self._table.starts_at(lines, index)
        )

    # --- rendering helpers ------------------------------------------------

    def _render_table(self, header: list[str], body_rows: list[list[str]]) -> str:
        head_cells = "".join(f"<th>{self._inline.to_html(cell)}</th>" for cell in header)
        parts = [f"<table><thead><tr>{head_cells}</tr></thead><tbody>"]
        for row in body_rows:
            padded = self._table.pad(row, len(header))
            cells = "".join(f"<td>{self._inline.to_html(cell)}</td>" for cell in padded)
            parts.append(f"<tr>{cells}</tr>")
        parts.append("</tbody></table>")
        return "".join(parts)

    def _render_list(
        self, items: list[tuple[str, str, str]], index: int, depth: int
    ) -> tuple[str, int]:
        """Render items at `depth`, recursing into deeper-indented runs. Returns (html, next index)."""
        tag = "ol" if items[index][1][0].isdigit() else "ul"
        parts = [f"<{tag}>"]
        while index < len(items):
            indent, _marker, content = items[index]
            level = len(indent) // self._INDENT_PER_LEVEL
            if level < depth:
                break
            if level > depth:
                nested, index = self._render_list(items, index, level)
                parts.append(self._attach_nested(parts.pop(), nested))
                continue
            parts.append(f"<li>{self._inline.to_html(content)}</li>")
            index += 1
        parts.append(f"</{tag}>")
        return "".join(parts), index

    def _attach_nested(self, previous: str, nested: str) -> str:
        """Put a nested list inside the preceding <li>, or in its own <li> when there is none."""
        closing = "</li>"
        if previous.endswith(closing):
            return previous[: -len(closing)] + nested + closing
        return previous + f"<li>{nested}</li>"


    def _unique_slug(self, text: str) -> str:
        base = self._SLUG_STRIP.sub("", text.lower()).strip()
        base = re.sub(r"[\s-]+", "-", base) or "section"
        candidate = base
        suffix = 2
        while candidate in self._slugs:
            candidate = f"{base}-{suffix}"
            suffix += 1
        self._slugs.add(candidate)
        return candidate

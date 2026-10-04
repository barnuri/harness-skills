#!/usr/bin/env python3
"""Render a design.md into a a formatted design.docx for the design review meeting.

Word is the realistic comment channel for product and non-engineering reviewers: they get track
changes and comments without installing anything. The output reuses the vendored docx template
so it carries the original styles, theme, heading numbering, headers/footers, and page setup.

Unlike the HTML renderer this path needs `python-docx`, which is bootstrapped into a venv beside
the script. That dependency is author-side only and never reaches a recipient.

Usage:
    python3 render_design_docx.py <design.md> [-o <design.docx>]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from design_front_matter import DesignFrontMatter
from docx_module_loader import DocxModuleLoader
from markdown_inline_parser import MarkdownInlineParser
from markdown_table import MarkdownTable


class DesignDocxRenderer:
    """Fills the docx template from a design markdown file."""

    _SKILL_ROOT = Path(__file__).resolve().parent.parent
    _TEMPLATE_PATH = _SKILL_ROOT / "assets" / "design-template.docx"

    _HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
    _FENCE = re.compile(r"^```")
    _LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s+(.*)$")
    _INLINE_MARKUP = re.compile(r"\*\*(.+?)\*\*|\*([^*\n]+?)\*|`([^`]+)`")
    _LATEX_BADGE = re.compile(r"\$\\color\{\w+\}\\textbf\{([^}]*)\}\$")
    # Same allowlist the HTML renderer uses: a permissive tag pattern eats the template's
    # <angle-bracket> placeholder prompts and leaves empty headings behind.
    _HTML_TAG = re.compile(
        rf"</?(?:{MarkdownInlineParser.INLINE_TAGS})\b(?:\s[^<>]*)?/?>", re.IGNORECASE
    )
    _HRULE = re.compile(r"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$")
    _HEADING_STYLES = {1: "Heading 1", 2: "Heading 2", 3: "Heading 3", 4: "Heading 4"}
    # The docx template ships List Paragraph but not List Bullet/List Number, and a paragraph
    # created here inherits no numbering definition — so the marker is written into the text.
    _LIST_STYLE = "List Paragraph"
    _TABLE_STYLE = "Table Grid"
    _BULLET_MARKER = "• "

    def __init__(self, docx_module) -> None:
        self._docx = docx_module
        self._front_matter = DesignFrontMatter()
        self._table = MarkdownTable()
        self._title = ""
        # When the front matter supplies the title, `#` is spent on the Title paragraph and the
        # document's real sections start at `##` — shift them up so they land on Heading 1, which
        # is the level the Word template numbers.
        self._heading_offset = 0

    def render(self, markdown_text: str, destination: Path) -> None:
        if not self._TEMPLATE_PATH.is_file():
            raise FileNotFoundError(f"docx template not found: {self._TEMPLATE_PATH}")
        front_matter, body = self._front_matter.split(markdown_text)
        document = self._docx.Document(str(self._TEMPLATE_PATH))
        self._clear_body(document)
        self._write_title_block(document, front_matter)
        self._write_body(document, body)
        document.save(str(destination))

    def _clear_body(self, document) -> None:
        """Strip the template's placeholder content, keeping its styles and section setup."""
        body = document.element.body
        for child in list(body):
            if child.tag.endswith("}sectPr"):
                continue
            body.remove(child)

    def _write_title_block(self, document, front_matter: dict[str, str]) -> None:
        title = front_matter.get("title", "Design")
        self._title = title
        self._heading_offset = 1 if front_matter.get("title") else 0
        self._add_paragraph(document, title, "Title")
        labels = (("Owner", "owner"), ("Team", "team"), ("Jira", "jira"), ("Status", "status"))
        parts = [f"{label}: {front_matter[key]}" for label, key in labels if front_matter.get(key)]
        if parts:
            self._add_paragraph(document, "   |   ".join(parts), None)

    def _write_body(self, document, body: str) -> None:
        lines = body.split("\n")
        index = 0
        while index < len(lines):
            line = lines[index]
            if not line.strip():
                index += 1
                continue
            index += self._write_block(document, lines, index)

    def _write_block(self, document, lines: list[str], start: int) -> int:
        line = lines[start]

        heading = self._HEADING.match(line)
        if heading:
            raw_level = len(heading.group(1))
            if raw_level == 1 and self._plain(heading.group(2)) == self._title:
                return 1  # already emitted as the Title paragraph
            level = max(1, min(raw_level - self._heading_offset, 4))
            self._add_paragraph(
                document, self._plain(heading.group(2)), self._HEADING_STYLES[level]
            )
            return 1

        if self._HRULE.match(line):
            return 1

        if self._FENCE.match(line):
            return self._write_code_block(document, lines, start)

        if self._table.starts_at(lines, start):
            return self._write_table(document, lines, start)

        item = self._LIST_ITEM.match(line)
        if item:
            marker = f"{item.group(1)} " if item.group(1)[0].isdigit() else self._BULLET_MARKER
            self._add_paragraph(
                document, f"{marker}{self._plain(item.group(2))}", self._LIST_STYLE
            )
            return 1

        if line.lstrip().startswith(">"):
            self._add_paragraph(document, self._plain(line.lstrip()[1:].strip()), None)
            return 1

        return self._write_paragraph(document, lines, start)

    def _write_paragraph(self, document, lines: list[str], start: int) -> int:
        """Join soft-wrapped lines into one Word paragraph, matching how the HTML renderer reads
        them. Emitting one paragraph per source line fragments spacing in the meeting document and
        attaches comments and track-changes to the wrong unit."""
        end = start
        collected: list[str] = []
        while end < len(lines) and lines[end].strip() and not self._starts_new_block(lines, end):
            collected.append(lines[end].strip())
            end += 1
        if not collected:
            return 1
        self._add_paragraph(document, self._plain(" ".join(collected)), None)
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

    def _add_paragraph(self, document, text: str, style: str | None):
        """Apply `style` when the template defines it, falling back to the default paragraph."""
        if style is None:
            return document.add_paragraph(text)
        try:
            return document.add_paragraph(text, style=style)
        except KeyError:
            return document.add_paragraph(text)

    def _write_code_block(self, document, lines: list[str], start: int) -> int:
        end = start + 1
        while end < len(lines) and not self._FENCE.match(lines[end]):
            end += 1
        for content_line in lines[start + 1 : end]:
            self._add_paragraph(document, content_line, None)
        return (end - start) + (1 if end < len(lines) else 0)

    def _write_table(self, document, lines: list[str], start: int) -> int:
        header = self._table.split_row(lines[start])
        end = self._table.body_end(lines, start)
        if not any(cell for cell in header):
            # Layout table with no header text (the template's metadata grid) — the title block
            # already carries those fields, so an empty-headed table is noise in Word.
            return end - start
        rows = [self._table.split_row(line) for line in lines[start + 2 : end]]
        table = document.add_table(rows=1, cols=len(header))
        self._apply_table_style(table)
        for cell, text in zip(table.rows[0].cells, header):
            cell.text = self._plain(text)
        for row in rows:
            padded = self._table.pad(row, len(header))
            for cell, text in zip(table.add_row().cells, padded):
                cell.text = self._plain(text)
        return end - start

    def _apply_table_style(self, table) -> None:
        """Borders come from Table Grid; a template without it still renders, just unruled."""
        try:
            table.style = self._TABLE_STYLE
        except KeyError:
            pass


    def _plain(self, text: str) -> str:
        """Word carries its own styling — reduce markdown/HTML decoration to readable text."""
        text = self._LATEX_BADGE.sub(r"[\1]", text)
        text = self._HTML_TAG.sub("", text)
        text = self._INLINE_MARKUP.sub(
            lambda m: m.group(1) or m.group(2) or m.group(3), text
        )
        return text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").strip()



def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render design.md into a a formatted design.docx"
    )
    parser.add_argument("source", type=Path, help="path to design.md")
    parser.add_argument("-o", "--output", type=Path, help="output path (default: alongside source)")
    args = parser.parse_args()

    if not args.source.is_file():
        print(f"error: no such file: {args.source}", file=sys.stderr)
        return 1

    destination = args.output or args.source.with_suffix(".docx")
    try:
        docx_module = DocxModuleLoader().load()
        DesignDocxRenderer(docx_module).render(
            args.source.read_text(encoding="utf-8"), destination
        )
    except (ImportError, FileNotFoundError, subprocess.CalledProcessError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    print(f"{destination} ({destination.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

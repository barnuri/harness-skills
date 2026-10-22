from __future__ import annotations

import re
import zipfile
from pathlib import Path
from typing import ClassVar
from xml.etree import ElementTree


class DocxTextReader:
    """Reads a .docx with the standard library only: body paragraphs as Markdown (headings and
    tables kept) and Word review comments as a list."""

    _NS: ClassVar[dict[str, str]] = {
        "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    }
    _W = "{" + _NS["w"] + "}"
    _HEADING_STYLE = re.compile(r"^(?:Heading|heading)\s?(\d)$")
    _BODY_PART = "word/document.xml"
    _COMMENTS_PART = "word/comments.xml"

    def read(self, path: Path) -> tuple[str, list[dict]]:
        try:
            with zipfile.ZipFile(path) as archive:
                body = self._read_body(archive.read(self._BODY_PART))
                comments = self._read_comments(archive)
        except (zipfile.BadZipFile, KeyError, ElementTree.ParseError) as err:
            raise ValueError(f"{path} is not a readable .docx: {err}") from err
        return body, comments

    def _read_body(self, xml_bytes: bytes) -> str:
        body = ElementTree.fromstring(xml_bytes).find("w:body", self._NS)
        if body is None:
            return ""
        blocks: list[str] = []
        for element in body:
            if element.tag == self._W + "p":
                blocks.append(self._paragraph(element))
            elif element.tag == self._W + "tbl":
                blocks.append(self._table(element))
        return "\n\n".join(block for block in blocks if block.strip()) + "\n"

    def _paragraph(self, paragraph: ElementTree.Element) -> str:
        text = self._text(paragraph)
        style = paragraph.find("w:pPr/w:pStyle", self._NS)
        style_name = style.get(self._W + "val", "") if style is not None else ""
        if style_name == "Title":
            return f"# {text}"
        heading = self._HEADING_STYLE.match(style_name)
        if heading:
            return "#" * (int(heading.group(1)) + 1) + f" {text}"
        if paragraph.find("w:pPr/w:numPr", self._NS) is not None:
            return f"- {text}"
        return text

    def _table(self, table: ElementTree.Element) -> str:
        rows = []
        for row in table.findall("w:tr", self._NS):
            cells = [
                " ".join(self._text(cell).split())
                for cell in row.findall("w:tc", self._NS)
            ]
            rows.append("| " + " | ".join(cells) + " |")
        return "\n".join(rows)

    def _text(self, element: ElementTree.Element) -> str:
        pieces = []
        for node in element.iter():
            if node.tag == self._W + "t" and node.text:
                pieces.append(node.text)
            elif node.tag == self._W + "tab":
                pieces.append("\t")
            elif node.tag in (self._W + "br", self._W + "cr"):
                pieces.append("\n")
        return "".join(pieces).strip()

    def _read_comments(self, archive: zipfile.ZipFile) -> list[dict]:
        if self._COMMENTS_PART not in archive.namelist():
            return []
        root = ElementTree.fromstring(archive.read(self._COMMENTS_PART))
        return [
            {
                "author": comment.get(self._W + "author") or "Anonymous",
                "created": comment.get(self._W + "date") or "",
                "body": self._text(comment),
            }
            for comment in root.findall("w:comment", self._NS)
        ]

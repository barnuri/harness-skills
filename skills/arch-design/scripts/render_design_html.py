#!/usr/bin/env python3
"""Render a design.md into one self-contained design.html.

The output must open with no network access and nothing installed: CSS is inlined, fonts come from
the system stack, and the mermaid bundle is inlined only when the document actually contains a
```mermaid block (it is 3.4 MB, so diagram-free documents stay small).

Usage:
    python3 render_design_html.py <design.md> [-o <design.html>]
"""

from __future__ import annotations

import argparse
import getpass
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from design_front_matter import DesignFrontMatter
from markdown_block_parser import MarkdownBlockParser


class DesignHtmlRenderer:
    """Assembles a complete standalone HTML document from a design markdown file."""

    _ASSETS = Path(__file__).resolve().parent.parent / "assets"
    _CSS_PATH = _ASSETS / "design.css"
    _MERMAID_PATH = _ASSETS / "mermaid.min.js"
    _ANNOTATE_CSS_PATH = _ASSETS / "annotate.css"
    _ANNOTATE_JS_PATH = _ASSETS / "annotate.js"
    _COMMENT_BLOCK_ID = "design-comments"
    # A browser cannot read $USER, so the author is resolved here, on the machine that renders.
    _AUTHOR_ENV_VARS = ("DESIGN_AUTHOR", "USER", "USERNAME", "LOGNAME")
    _EMBEDDED_COMMENTS = re.compile(
        r'<script[^>]*id="design-comments"[^>]*>(.*?)</script>', re.DOTALL
    )
    _META_FIELDS = ("owner", "team", "jira", "epic", "area", "date")

    # A bare ticket key is not clickable, and a reviewer who wants the ticket then has to go
    # find it. When a browse URL is configured, anything that looks like a ticket key links to it.
    _JIRA_BASE_URL_FIELD = "jira_base_url"
    _JIRA_BASE_URL_ENV = "DESIGN_JIRA_BASE_URL"
    _JIRA_KEY = re.compile(r"^[A-Z][A-Z0-9_]+-\d+$")
    _LINK_FIELDS = ("jira", "epic")
    _STATUS_CLASSES = {
        "draft": "status-draft",
        "in review": "status-review",
        "approved": "status-approved",
    }

    def __init__(self, annotate: bool = True, source_name: str = "") -> None:
        self._parser = MarkdownBlockParser()
        self._front_matter = DesignFrontMatter()
        self._annotate = annotate
        self.source_name = source_name

    def render(self, markdown_text: str, comments: list | None = None) -> str:
        front_matter, body = self._front_matter.split(markdown_text)
        body_html = self._collapse_sections(self._parser.to_html(body))
        self.validate_mermaid()
        title = front_matter.get("title") or self._first_heading() or "Design"
        return self._document(
            title=title,
            meta_html=self._render_meta(front_matter),
            toc_html=self._render_toc(),
            body_html=body_html,
            mermaid_script=self._render_mermaid_script(),
            annotate_html=self._render_annotate(title, front_matter, comments or []),
        )

    def author_name(self, front_matter: dict[str, str]) -> str:
        """Who rendered the document. The front matter wins; otherwise fall back to the account."""
        explicit = front_matter.get("owner")
        if explicit:
            return explicit
        for variable in self._AUTHOR_ENV_VARS:
            value = os.environ.get(variable)
            if value:
                return value
        try:
            return getpass.getuser()
        except Exception:
            return "Unknown"

    def existing_comments(self, path: Path) -> list:
        """Recover review comments already embedded in a previously annotated render."""
        if not path.is_file():
            return []
        match = self._EMBEDDED_COMMENTS.search(path.read_text(encoding="utf-8"))
        if not match:
            return []
        try:
            parsed = json.loads(match.group(1) or "[]")
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []

    def _render_annotate(
        self, title: str, front_matter: dict[str, str], comments: list
    ) -> str:
        if not self._annotate:
            return ""
        if not self._ANNOTATE_CSS_PATH.is_file() or not self._ANNOTATE_JS_PATH.is_file():
            raise FileNotFoundError(f"annotation assets missing under {self._ASSETS}")
        config = {
            "author": self.author_name(front_matter),
            "title": title,
            "documentId": front_matter.get("jira") or title,
            "jira": front_matter.get("jira", ""),
            "sourcePath": self.source_name,
        }
        return (
            f"<style>\n{self._ANNOTATE_CSS_PATH.read_text(encoding='utf-8')}\n</style>\n"
            f'<script type="application/json" id="{self._COMMENT_BLOCK_ID}">'
            f"{self._safe_json(comments)}</script>\n"
            f"<script>window.__DESIGN_ANNOTATE__ = {self._safe_json(config)};</script>\n"
            f"<script>\n{self._ANNOTATE_JS_PATH.read_text(encoding='utf-8')}\n</script>"
        )

    def _safe_json(self, value) -> str:
        """`</script>` inside embedded JSON would terminate the block early."""
        return json.dumps(value).replace("</", "<\\/")



    # Sections nobody reads top-to-bottom but everybody wants present. Rendered as a closed
    # <details> so they cost one line of page instead of half a screen. The <h2> stays inside
    # <summary>, which keeps its id visible as a link target and keeps it in the table of contents.
    _COLLAPSED_SECTIONS = ("document-history",)

    def _collapse_sections(self, body_html: str) -> str:
        for anchor in self._COLLAPSED_SECTIONS:
            pattern = re.compile(
                rf'(<h2 id="{re.escape(anchor)}">.*?</h2>)(.*?)(?=<h2 |<hr>|\Z)',
                re.DOTALL,
            )
            body_html = pattern.sub(self._as_details, body_html, count=1)
        return body_html

    @staticmethod
    def _as_details(match: "re.Match[str]") -> str:
        heading, content = match.group(1), match.group(2)
        return (
            f'<details class="collapsible-section">'
            f"<summary>{heading}</summary>"
            f'<div class="collapsible-body">{content}</div>'
            f"</details>"
        )

    def _first_heading(self) -> str:
        for level, text, _anchor in self._parser.headings:
            if level == 1:
                return text
        return ""

    def _render_meta(self, front_matter: dict[str, str]) -> str:
        cells: list[str] = []
        status = front_matter.get("status", "")
        if status:
            css_class = self._STATUS_CLASSES.get(status.lower(), "status-draft")
            cells.append(
                f'<div><span class="k">Status</span>'
                f'<span class="status {css_class}">{html.escape(status)}</span></div>'
            )
        for field in self._META_FIELDS:
            value = front_matter.get(field)
            if not value:
                continue
            cells.append(
                f'<div><span class="k">{field.capitalize()}</span>'
                f'<span class="v">{self._meta_value_html(field, value, front_matter)}</span></div>'
            )
        if not cells:
            return ""
        return f'<div class="meta">{"".join(cells)}</div>'

    def _jira_base_url(self, front_matter: dict[str, str]) -> str:
        return front_matter.get(self._JIRA_BASE_URL_FIELD) or os.environ.get(
            self._JIRA_BASE_URL_ENV, ""
        )

    def _meta_value_html(self, field: str, value: str, front_matter: dict[str, str]) -> str:
        """Jira and epic render as links; every other field is plain escaped text."""
        if field not in self._LINK_FIELDS:
            return html.escape(value)
        text = value.strip()
        base_url = self._jira_base_url(front_matter)
        if self._JIRA_KEY.match(text):
            if not base_url:
                return html.escape(text)
            return self._link(base_url + text, text)
        if text.startswith(("http://", "https://")):
            # A pasted browse URL still reads as the ticket key: the label is the key, the href
            # is the URL. Only the key is shown, never the full URL.
            tail = text.rstrip("/").rsplit("/", 1)[-1]
            label = tail if self._JIRA_KEY.match(tail) else text
            return self._link(text, label)
        return html.escape(value)

    @staticmethod
    def _link(href: str, label: str) -> str:
        return f'<a href="{html.escape(href, quote=True)}">{html.escape(label)}</a>'

    def _render_toc(self) -> str:
        entries = [h for h in self._parser.headings if h[0] in (2, 3)]
        if not entries:
            return ""
        items = "".join(
            f'<li class="lvl-{level}"><a href="#{anchor}">{html.escape(text)}</a></li>'
            for level, text, anchor in entries
        )
        return f'<nav class="toc"><p class="toc-title">Contents</p><ul>{items}</ul></nav>'

    def _render_mermaid_script(self) -> str:
        if not self._parser.has_mermaid:
            return ""
        if not self._MERMAID_PATH.is_file():
            raise FileNotFoundError(
                f"document contains a mermaid diagram but the vendored bundle is missing: "
                f"{self._MERMAID_PATH}"
            )
        bundle = self._MERMAID_PATH.read_text(encoding="utf-8")
        return f"<script>{bundle}</script>\n<script>{self._MERMAID_THEME_JS}</script>"

    # Mermaid has no runtime theme switch: a diagram keeps the colours it was rendered with.
    # Rendered once under the light theme, its #333 edges and light label chips are unreadable
    # once the page flips to dark. So keep each diagram's source and re-render on every change
    # of body.theme-dark. Decoupled from annotate.js on purpose — this also works with
    # --no-annotate, where the class is set from prefers-color-scheme instead of a toggle.
    _MERMAID_THEME_JS = """
(function () {
  var blocks = Array.prototype.slice.call(document.querySelectorAll('.mermaid'));
  blocks.forEach(function (el) { el.dataset.src = el.textContent; });
  var last = null;
  function render() {
    var dark = document.body.classList.contains('theme-dark');
    if (dark === last) { return; }
    last = dark;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: dark ? 'dark' : 'default',
      darkMode: dark,
      themeVariables: dark ? {background: '#0d1117', mainBkg: '#1b2530', lineColor: '#8b98a5',
                             textColor: '#e6edf3', edgeLabelBackground: '#0d1117'} : {}
    });
    blocks.forEach(function (el) {
      el.removeAttribute('data-processed');
      el.textContent = el.dataset.src;
    });
    mermaid.run({nodes: blocks});
  }
  render();
  new MutationObserver(render).observe(document.body, {
    attributes: true, attributeFilter: ['class']
  });
})();
"""

    _MERMAID_CHECK = Path(__file__).resolve().parent / "check_mermaid.mjs"
    _MERMAID_CHECK_DEPS = Path(__file__).resolve().parent.parent / ".mermaid-check"

    def validate_mermaid(self) -> None:
        """Parse every mermaid block with the same bundle the browser will use.

        An invalid diagram does not fail the render — it renders a red "Syntax error in text"
        bomb in the middle of the document, which is only ever discovered by a human opening the
        file. Catching it here is the difference between a build error and a reviewer seeing it.

        Silently skipped when node is unavailable; that keeps the renderer stdlib-only in spirit.
        """
        blocks = self._parser.mermaid_blocks
        if not blocks or shutil.which("node") is None:
            return
        if not self._ensure_check_deps():
            return
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(blocks, handle)
            payload = handle.name
        try:
            result = subprocess.run(
                ["node", str(self._MERMAID_CHECK), payload],
                capture_output=True,
                text=True,
                cwd=str(self._MERMAID_CHECK_DEPS),
                timeout=120,
            )
        except (OSError, subprocess.SubprocessError):
            return
        finally:
            os.unlink(payload)
        if result.returncode != 0:
            raise ValueError(f"invalid mermaid diagram\n{result.stderr.strip()}")

    def _ensure_check_deps(self) -> bool:
        """Install jsdom beside the skill on first use. DOMPurify needs a real DOM to load."""
        if (self._MERMAID_CHECK_DEPS / "node_modules" / "jsdom").is_dir():
            return True
        if shutil.which("npm") is None:
            return False
        self._MERMAID_CHECK_DEPS.mkdir(exist_ok=True)
        try:
            subprocess.run(
                ["npm", "install", "--silent", "--no-audit", "--no-fund", "jsdom"],
                cwd=str(self._MERMAID_CHECK_DEPS),
                capture_output=True,
                timeout=300,
                check=True,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        return (self._MERMAID_CHECK_DEPS / "node_modules" / "jsdom").is_dir()

    def _read_css(self) -> str:
        if not self._CSS_PATH.is_file():
            raise FileNotFoundError(f"stylesheet not found: {self._CSS_PATH}")
        return self._CSS_PATH.read_text(encoding="utf-8")

    def _document(
        self,
        title: str,
        meta_html: str,
        toc_html: str,
        body_html: str,
        mermaid_script: str,
        annotate_html: str = "",
    ) -> str:
        return (
            "<!doctype html>\n"
            '<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f"<title>{html.escape(title)}</title>\n"
            f"<style>\n{self._read_css()}\n</style>\n"
            "</head>\n<body>\n"
            f'<div class="layout">{toc_html}<main class="doc">{meta_html}{body_html}</main></div>\n'
            f"{mermaid_script}\n{annotate_html}\n"
            "</body>\n</html>\n"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Render design.md into a self-contained design.html")
    parser.add_argument("source", type=Path, help="path to design.md")
    parser.add_argument("-o", "--output", type=Path, help="output path (default: alongside source)")
    parser.add_argument(
        "--no-annotate",
        action="store_true",
        help="omit the review-annotation layer (clean copy for printing or archiving)",
    )
    parser.add_argument(
        "--comments",
        type=Path,
        help="annotated HTML or comments JSON to carry review comments over from",
    )
    args = parser.parse_args()

    if not args.source.is_file():
        print(f"error: no such file: {args.source}", file=sys.stderr)
        return 1

    destination = args.output or args.source.with_suffix(".html")
    renderer = DesignHtmlRenderer(annotate=not args.no_annotate, source_name=str(args.source))
    # Re-rendering must not throw away review comments the recipient already wrote, so seed from
    # an explicit source when given, otherwise from whatever is already at the destination.
    carried = renderer.existing_comments(args.comments or destination)
    try:
        rendered = renderer.render(args.source.read_text(encoding="utf-8"), carried)
    except ValueError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    destination.write_text(rendered, encoding="utf-8")
    if carried:
        print(f"carried over {len(carried)} review comment(s)", file=sys.stderr)
    print(f"{destination} ({len(rendered.encode('utf-8')):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

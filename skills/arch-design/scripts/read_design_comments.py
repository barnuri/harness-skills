#!/usr/bin/env python3
"""Read review comments out of an annotated design.html (or a comments JSON export).

This is how a reviewer's notes come back to the agent: the reviewer saves the annotated file,
emails it, and the agent runs this to get an actionable list instead of opening a 50 KB HTML in
its context. Section anchors are printed so each comment can be traced to the part of the design
it is about.

Usage:
    python3 read_design_comments.py <design.annotated.html> [--status open|sent|resolved|all]
                                    [--format markdown|json]
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path


class DesignCommentReader:
    """Extracts and formats the embedded comment record."""

    _EMBEDDED = re.compile(r'<script[^>]*id="design-comments"[^>]*>(.*?)</script>', re.DOTALL)
    _STATUS_ORDER = {"open": 0, "sent": 1, "resolved": 2}

    def load(self, path: Path) -> list[dict]:
        text = path.read_text(encoding="utf-8")
        if path.suffix.lower() == ".json":
            return self._decode(text)
        match = self._EMBEDDED.search(text)
        if not match:
            return []
        # The renderer escapes `</` when embedding so the block cannot terminate early.
        return self._decode(match.group(1).replace("<\\/", "</"))

    def _decode(self, raw: str) -> list[dict]:
        try:
            parsed = json.loads(raw or "[]")
        except json.JSONDecodeError as err:
            raise ValueError(f"comment block is not valid JSON: {err}") from err
        return parsed if isinstance(parsed, list) else []

    def filter(self, comments: list[dict], status: str) -> list[dict]:
        if status == "all":
            return comments
        return [c for c in comments if (c.get("status") or "open") == status]

    def sort(self, comments: list[dict]) -> list[dict]:
        return sorted(
            comments,
            key=lambda c: (
                self._STATUS_ORDER.get(c.get("status") or "open", 9),
                c.get("created") or "",
            ),
        )

    def to_markdown(self, comments: list[dict], source: Path) -> str:
        if not comments:
            return f"No matching review comments in {source}."
        reviewers = sorted({c.get("author") or "Anonymous" for c in comments})
        lines = [
            f"# Review comments — {source.name}",
            "",
            f"{len(comments)} comment(s) from: {', '.join(reviewers)}",
            "",
        ]
        for index, comment in enumerate(self.sort(comments), start=1):
            anchor = comment.get("anchor") or {}
            section = anchor.get("section") or ""
            heading = f"## {index}. {comment.get('author') or 'Anonymous'}"
            if section:
                heading += f" — `#{section}`"
            lines.append(heading)
            lines.append("")
            lines.append(
                f"**Status:** {comment.get('status') or 'open'} · "
                f"**Written:** {(comment.get('created') or '')[:10]}"
            )
            lines.append("")
            quote = anchor.get("quote")
            if quote:
                lines.append(f"> {html.unescape(quote).strip()}")
                lines.append("")
            lines.append(comment.get("body") or "")
            lines.append("")
            for reply in comment.get("replies") or []:
                lines.append(f"- **{reply.get('author') or 'Anonymous'}:** {reply.get('body') or ''}")
            if comment.get("replies"):
                lines.append("")
        return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract review comments from an annotated design.html"
    )
    parser.add_argument("source", type=Path, help="annotated .html or .comments.json")
    parser.add_argument(
        "--status",
        default="all",
        choices=("open", "sent", "resolved", "all"),
        help="only show comments in this state (default: all)",
    )
    parser.add_argument(
        "--format", default="markdown", choices=("markdown", "json"), help="output format"
    )
    args = parser.parse_args()

    if not args.source.is_file():
        print(f"error: no such file: {args.source}", file=sys.stderr)
        return 1

    reader = DesignCommentReader()
    try:
        comments = reader.filter(reader.load(args.source), args.status)
    except ValueError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps(reader.sort(comments), indent=2))
    else:
        print(reader.to_markdown(comments, args.source))
    return 0


if __name__ == "__main__":
    sys.exit(main())

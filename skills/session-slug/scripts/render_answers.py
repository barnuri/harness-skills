#!/usr/bin/env python3
"""Render the session answer log as deterministic, self-contained HTML.

Each `### ` entry becomes one card. A `---` line or a `## ` heading closes the open card.
"""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

TITLE = "Session Answers"
INLINE_CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
ITALIC = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)")
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
RULE = re.compile(r"^\s*(-{3,}|\*{3,})\s*$")
ITEM = re.compile(r"^\s*[-*+]\s+(.+)$")
QUOTE = re.compile(r"^>\s?(.*)$")


def inline_markup(text: str) -> str:
    escaped = html.escape(text, quote=True)
    escaped = INLINE_CODE.sub(r"<code>\1</code>", escaped)
    escaped = BOLD.sub(r"<strong>\1</strong>", escaped)
    return ITALIC.sub(r"<em>\1</em>", escaped)


def render_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    output: list[str] = []
    paragraph: list[str] = []
    list_items: list[str] = []
    quote: list[str] = []
    fenced_code: list[str] | None = None
    card_open = False
    card_body_open = False

    def flush_paragraph() -> None:
        if paragraph:
            output.append(f"<p>{inline_markup(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_list() -> None:
        if list_items:
            items = "".join(f"<li>{inline_markup(item)}</li>" for item in list_items)
            output.append(f"<ul>{items}</ul>")
            list_items.clear()

    def flush_quote() -> None:
        if quote:
            output.append(f"<blockquote>{inline_markup(' '.join(quote))}</blockquote>")
            quote.clear()

    def flush_all() -> None:
        flush_paragraph()
        flush_list()
        flush_quote()

    def close_card() -> None:
        nonlocal card_open, card_body_open
        flush_all()
        if card_open:
            if card_body_open:
                output.append("</div>")
                card_body_open = False
            output.append("</div>")
            card_open = False

    for line in lines:
        if fenced_code is not None:
            if line.startswith("```"):
                output.append(f"<pre><code>{html.escape(chr(10).join(fenced_code))}</code></pre>")
                fenced_code = None
            else:
                fenced_code.append(line)
            continue
        if line.startswith("```"):
            flush_all()
            fenced_code = []
            continue
        if RULE.match(line):
            close_card()
            continue
        if not line.strip():
            flush_all()
            continue
        heading = HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            if level <= 2:
                close_card()
                output.append(f"<h{level}>{inline_markup(heading.group(2))}</h{level}>")
            else:
                close_card()
                output.append('<div class="qa-card">')
                card_open = True
                qa_heading = re.match(r"^([QO]\d+)\s+[—–:-]\s+(.+)$", heading.group(2))
                if qa_heading:
                    number, question = qa_heading.groups()
                    output.append(
                        f'<div class="qa-heading"><span class="qa-number">{inline_markup(number)}</span><h{level}>{inline_markup(question)}</h{level}></div>',
                    )
                    output.append('<div class="qa-body">')
                    card_body_open = True
                else:
                    output.append(f"<h{level}>{inline_markup(heading.group(2))}</h{level}>")
            continue
        quoted = QUOTE.match(line)
        if quoted:
            flush_paragraph()
            flush_list()
            quote.append(quoted.group(1))
            continue
        item = ITEM.match(line)
        if item:
            flush_paragraph()
            flush_quote()
            list_items.append(item.group(1))
            continue
        flush_list()
        flush_quote()
        paragraph.append(line.strip())

    if fenced_code is not None:
        output.append(f"<pre><code>{html.escape(chr(10).join(fenced_code))}</code></pre>")
    close_card()
    return "\n".join(output)


def render_document(markdown: str) -> str:
    body = render_markdown(markdown)
    title = html.escape(TITLE)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Readable answers recorded during this work session.">
<title>{title}</title>
<style>
:root {{ color-scheme: light dark; --bg: #f4f6f9; --panel: #ffffff; --card: #ffffff; --text: #172033; --muted: #42526d; --accent: #1362bb; --line: #d9e0ea; --code: #eef2f7; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #101820; --panel: #18212b; --card: #1d2834; --text: #edf2f8; --muted: #c1ccda; --accent: #8ac1ff; --line: #3a4859; --code: #263545; }} }}
:root[data-theme="light"] {{ color-scheme: light; --bg: #f4f6f9; --panel: #ffffff; --card: #ffffff; --text: #172033; --muted: #42526d; --accent: #1362bb; --line: #d9e0ea; --code: #eef2f7; }}
:root[data-theme="dark"] {{ color-scheme: dark; --bg: #101820; --panel: #18212b; --card: #1d2834; --text: #edf2f8; --muted: #c1ccda; --accent: #8ac1ff; --line: #3a4859; --code: #263545; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; padding: 28px 16px; background: var(--bg); color: var(--text); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
main {{ max-width: 760px; margin: 0 auto; padding: 28px clamp(18px, 4vw, 36px); background: var(--panel); border: 1px solid var(--line); border-radius: 12px; }}
h1 {{ margin: 0 0 .25rem; font-size: clamp(1.7rem, 4.5vw, 2.15rem); line-height: 1.2; }}
h2 {{ margin: 2rem 0 .8rem; font-size: 1.2rem; line-height: 1.3; }}
h3 {{ margin: 0; font-size: 1rem; line-height: 1.4; }}
blockquote {{ margin: 0 0 1.25rem; color: var(--muted); font-size: .9rem; }}
.qa-card {{ margin: 0 0 .9rem; overflow: hidden; background: var(--card); border: 1px solid var(--line); border-radius: 9px; }}
.qa-heading {{ display: flex; align-items: flex-start; gap: .75rem; padding: 1rem 1.1rem; }}
.qa-number {{ display: inline-flex; flex: 0 0 2rem; align-items: center; justify-content: center; min-height: 2rem; border-radius: 6px; background: var(--code); color: var(--muted); font: 600 .75rem/1 ui-monospace, SFMono-Regular, Menlo, monospace; }}
.qa-heading h3 {{ padding-top: .18rem; }}
.qa-body {{ padding: 0 1.1rem 1rem 3.85rem; color: var(--muted); }}
.qa-body p {{ margin: 0; }}
p {{ margin: .55rem 0; }}
ul {{ padding-left: 1.25rem; }}
li + li {{ margin-top: .3rem; }}
strong {{ color: var(--text); }}
code {{ padding: .12em .36em; border-radius: 4px; background: var(--code); font: .9em ui-monospace, SFMono-Regular, Menlo, monospace; }}
pre {{ overflow-x: auto; padding: 14px; border: 1px solid var(--line); border-radius: 8px; background: var(--code); }}
pre code {{ padding: 0; }}
@media (max-width: 520px) {{ body {{ padding: 12px; }} main {{ padding: 22px 16px; border-radius: 10px; }} .qa-heading {{ padding: .85rem; }} .qa-body {{ padding: 0 .85rem .9rem 3.55rem; }} }}
</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Render answers.md to a self-contained answers.html.")
    parser.add_argument("source", type=Path, help="Path to answers.md")
    args = parser.parse_args()
    source = args.source.resolve()
    if source.name != "answers.md":
        parser.error("source file must be named answers.md")
    destination = source.with_name("answers.html")
    markdown = source.read_text(encoding="utf-8")
    destination.write_text(render_document(markdown), encoding="utf-8", newline="\n")
    print(destination)


if __name__ == "__main__":
    main()

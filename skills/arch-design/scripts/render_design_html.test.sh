#!/usr/bin/env bash
# Tests for render_design_html.py — design.md -> one self-contained design.html.
#
# The load-bearing case is Case 8: the design template is full of <angle-bracket> placeholder
# prompts, and a permissive raw-HTML passthrough swallows them as unknown elements so they render
# blank in the browser — the author sees an empty section instead of the prompt telling them what
# to write. The fixture asserts they survive as escaped text.
#
# Case 9 guards the other constraint that matters: the rendered file must open with no network,
# and the 3.4 MB mermaid bundle must only be paid for by documents that actually have a diagram.
#
# Run: bash render_design_html.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render_design_html.py"

failures=0
pass_count=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass_count=$((pass_count + 1))
    return
  fi
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
  failures=$((failures + 1))
}

# check_contains <label> <needle> <file> — asserts the needle appears at least once.
check_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then
    pass_count=$((pass_count + 1))
    return
  fi
  printf 'FAIL: %s\n  missing: %s\n' "$label" "$needle" >&2
  failures=$((failures + 1))
}

# check_absent <label> <needle> <file>
check_absent() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then
    printf 'FAIL: %s\n  unexpectedly present: %s\n' "$label" "$needle" >&2
    failures=$((failures + 1))
    return
  fi
  pass_count=$((pass_count + 1))
}

# Global CLAUDE.md forbids rm for deletions; use trash when it exists, otherwise leave the
# mktemp directory for the OS to reap rather than reaching for rm.
cleanup() {
  local target="$1"
  if command -v trash >/dev/null 2>&1; then
    trash "$target" >/dev/null 2>&1
  fi
}

work=$(mktemp -d)

# --- Case 1: front matter becomes the metadata header and status chip -------
cat >"$work/fm.md" <<'EOF'
---
title: Host Config Compliance
status: In review
owner: Yehoda
team: Platform
jira: PROJ-1234
area: cspm
date: 2026-08-30
---

# Host Config Compliance

## Background

Some prose.
EOF
python3 "$SCRIPT" "$work/fm.md" -o "$work/fm.html" >/dev/null
check_contains "Case 1: title in <title>" "<title>Host Config Compliance</title>" "$work/fm.html"
check_contains "Case 1: status chip class" 'class="status status-review"' "$work/fm.html"
check_contains "Case 1: owner in meta" "Yehoda" "$work/fm.html"
check_contains "Case 1: jira in meta" "PROJ-1234" "$work/fm.html"

# --- Case 2: headings produce anchors and a table of contents ---------------
check_contains "Case 2: h2 anchor" '<h2 id="background">Background</h2>' "$work/fm.html"
check_contains "Case 2: toc link" '<a href="#background">Background</a>' "$work/fm.html"

# --- Case 3: tables ---------------------------------------------------------
cat >"$work/table.md" <<'EOF'
# T

| Area | Approver |
|------|----------|
| Product | |
| Architecture | Alex |
EOF
python3 "$SCRIPT" "$work/table.md" -o "$work/table.html" >/dev/null
check_contains "Case 3: table header" "<th>Area</th>" "$work/table.html"
check_contains "Case 3: table cell" "<td>Architecture</td>" "$work/table.html"
check_contains "Case 3: empty cell padded" "<td></td>" "$work/table.html"

# --- Case 4: nested lists ---------------------------------------------------
cat >"$work/list.md" <<'EOF'
# L

- top one
  - nested one
- top two

1. first
2. second
EOF
python3 "$SCRIPT" "$work/list.md" -o "$work/list.html" >/dev/null
check_contains "Case 4: unordered list" "<li>top one" "$work/list.html"
check_contains "Case 4: nested ul" "<ul><li>nested one</li></ul>" "$work/list.html"
check_contains "Case 4: ordered list" "<ol>" "$work/list.html"

# Lazy continuation: a wrapped bullet used to close the list, leaving the remainder as a
# full-width paragraph outside the <li>.
cat >"$work/wrap-list.md" <<'EOF'
# W

- first item that wraps
  onto a second line
- second item
  - nested wrapped
    continues here

A normal paragraph.
EOF
python3 "$SCRIPT" "$work/wrap-list.md" -o "$work/wrap-list.html" --no-annotate >/dev/null
check_contains "Case 4: wrapped bullet stays in its <li>" \
  "<li>first item that wraps onto a second line</li>" "$work/wrap-list.html"
check_contains "Case 4: wrapped nested bullet joins too" \
  "<li>nested wrapped continues here</li>" "$work/wrap-list.html"
check_contains "Case 4: following paragraph is still a paragraph" \
  "<p>A normal paragraph.</p>" "$work/wrap-list.html"

# --- Case 5: fenced code is escaped, not interpreted -------------------------
cat >"$work/code.md" <<'EOF'
# C

```json
{"_id": "<id>", "n": 1}
```
EOF
python3 "$SCRIPT" "$work/code.md" -o "$work/code.html" >/dev/null
check_contains "Case 5: code fence class" '<pre><code class="language-json">' "$work/code.html"
check_contains "Case 5: code content escaped" "&lt;id&gt;" "$work/code.html"

# --- Case 6: blockquote ------------------------------------------------------
cat >"$work/quote.md" <<'EOF'
# Q

> Name the components, not the order.
EOF
python3 "$SCRIPT" "$work/quote.md" -o "$work/quote.html" >/dev/null
check_contains "Case 6: blockquote" "<blockquote>" "$work/quote.html"

# --- Case 7: SELECTED/DECISION badge markup survives -------------------------
cat >"$work/badge.md" <<'EOF'
# B

$\color{green}\textbf{DECISION}$ <strong style="color: #27ae60"><ins>**Decision:** use getResource</ins></strong>
EOF
python3 "$SCRIPT" "$work/badge.md" -o "$work/badge.html" >/dev/null
check_contains "Case 7: latex badge becomes chip" '<span class="badge">DECISION</span>' "$work/badge.html"
check_contains "Case 7: ins tag preserved" "<ins>" "$work/badge.html"
check_contains "Case 7: strong style preserved" 'style="color: #27ae60"' "$work/badge.html"
check_absent "Case 7: raw latex not left behind" '\color{green}' "$work/badge.html"

# --- Case 8: angle-bracket placeholders survive as visible text --------------
# Regression guard: a permissive raw-HTML pattern makes these vanish in the browser.
cat >"$work/ph.md" <<'EOF'
# P

<Every area below must be signed off before implementation starts.>

| By whom |
|---------|
| <name> |
EOF
python3 "$SCRIPT" "$work/ph.md" -o "$work/ph.html" >/dev/null
check_contains "Case 8: prose placeholder escaped" "&lt;Every area below" "$work/ph.html"
check_contains "Case 8: table placeholder escaped" "&lt;name&gt;" "$work/ph.html"
check_absent "Case 8: no raw <name> element" "<td><name></td>" "$work/ph.html"

# Regression: a prompt opening with an allowlisted tag name ("<A concrete example …>") used to
# become a bare unclosed <a> that swallowed the rest of the document.
cat >"$work/ph2.md" <<'EOF'
# P2

<A concrete example — a sample rule, request, or record.>

<Bold claim about the design.>

Tail paragraph.
EOF
python3 "$SCRIPT" "$work/ph2.md" -o "$work/ph2.html" >/dev/null
check_contains "Case 8: prose starting with a tag name is escaped" "&lt;A concrete example" "$work/ph2.html"
check_absent "Case 8: no bare anchor emitted" "<p><a></p>" "$work/ph2.html"
a_open=$(grep -o "<a[ >]" "$work/ph2.html" | wc -l | tr -d ' ')
check "Case 8: no stray anchors at all" "0" "$a_open"

# --- Case 9: mermaid inlined only when a diagram is present ------------------
cat >"$work/nodiag.md" <<'EOF'
# N

No diagram here.
EOF
python3 "$SCRIPT" "$work/nodiag.md" -o "$work/nodiag.html" >/dev/null
check_absent "Case 9: no mermaid bundle without a diagram" "mermaid.initialize" "$work/nodiag.html"
nodiag_bytes=$(wc -c <"$work/nodiag.html" | tr -d ' ')
# Bound is tight on purpose: a loose ceiling would not notice a partial bundle leak. It has to
# cover the ~62 KB annotation runtime, which every annotated render carries.
check "Case 9: diagram-free output stays small" "small" \
  "$([ "$nodiag_bytes" -lt 130000 ] && echo small || echo "large:$nodiag_bytes")"

cat >"$work/diag.md" <<'EOF'
# D

```mermaid
graph TD; A-->B;
```
EOF
python3 "$SCRIPT" "$work/diag.md" -o "$work/diag.html" >/dev/null
check_contains "Case 9: mermaid container emitted" '<div class="mermaid">' "$work/diag.html"
check_contains "Case 9: mermaid bundle inlined" "mermaid.initialize" "$work/diag.html"
diag_bytes=$(wc -c <"$work/diag.html" | tr -d ' ')
check "Case 9: diagram output carries the bundle" "large" \
  "$([ "$diag_bytes" -gt 1000000 ] && echo large || echo "small:$diag_bytes")"

# --- Case 10: the artifact is self-contained --------------------------------
# No stylesheet link, no script src, nothing FETCHED at open time. An <a href> to Jira is a
# hyperlink the reader may click, not a resource the browser loads, so it does not break
# offline opening -- only src= and <link href= would.
check_absent "Case 10: no external stylesheet" "<link" "$work/fm.html"
check_absent "Case 10: no script src" "<script src" "$work/fm.html"
check_contains "Case 10: css inlined" "<style>" "$work/fm.html"
fetched=$(grep -oE 'src="https?://[^"]*"' "$work/fm.html" | wc -l | tr -d ' ')
check "Case 10: zero fetched external resources" "0" "$fetched"
linked_css=$(grep -oE '<link[^>]+href="https?://[^"]*"' "$work/fm.html" | wc -l | tr -d ' ')
check "Case 10: zero linked stylesheets" "0" "$linked_css"

# --- Case 11: jira / epic front matter renders as a link --------------------
cat >"$work/jira.md" <<'EOF'
---
title: Ticket Linking
jira: PROJ-123
epic: PROJ-456
jira_base_url: https://issues.example.com/browse/
area: platform
---

# Ticket Linking

## Background

Text.
EOF
python3 "$SCRIPT" "$work/jira.md" -o "$work/jira.html" >/dev/null
check_contains "Case 11: jira key links to browse URL"   '<a href="https://issues.example.com/browse/PROJ-123">PROJ-123</a>' "$work/jira.html"
check_contains "Case 11: epic key links to browse URL"   '<a href="https://issues.example.com/browse/PROJ-456">PROJ-456</a>' "$work/jira.html"
check_absent "Case 11: the URL itself is never shown as text"   '>https://issues.example.com/browse/' "$work/jira.html"

sed '/^jira_base_url:/d' "$work/jira.md" >"$work/jira-nourl.md"
DESIGN_JIRA_BASE_URL=https://env.example.com/browse/ python3 "$SCRIPT" "$work/jira-nourl.md" -o "$work/jira-env.html" >/dev/null
check_contains "Case 11: env var supplies the browse URL" '<a href="https://env.example.com/browse/PROJ-123">PROJ-123</a>' "$work/jira-env.html"
env -u DESIGN_JIRA_BASE_URL python3 "$SCRIPT" "$work/jira-nourl.md" -o "$work/jira-plain.html" >/dev/null
check_absent "Case 11: no browse URL configured renders the key as plain text" '<a href="PROJ-123' "$work/jira-plain.html"
check_contains "Case 11: unlinked key is still shown" 'PROJ-123' "$work/jira-plain.html"

# --- Case 12: document history is collapsed by default ----------------------
cat >"$work/hist.md" <<'EOF'
---
title: Collapsing
area: platform
---

# Collapsing

## Document history

| Date | Change |
|------|--------|
| 2026-01-01 | First. |

## Background

Body text here.
EOF
python3 "$SCRIPT" "$work/hist.md" -o "$work/hist.html" >/dev/null
check_contains "Case 12: history wrapped in details"   '<details class="collapsible-section">' "$work/hist.html"
check_absent "Case 12: details is closed by default"   '<details class="collapsible-section" open>' "$work/hist.html"
check_contains "Case 12: heading is the summary"   '<summary><h2 id="document-history">Document history</h2></summary>' "$work/hist.html"
check_contains "Case 12: history table still present" "2026-01-01" "$work/hist.html"
check_contains "Case 12: next section is not swallowed"   '<h2 id="background">Background</h2>' "$work/hist.html"
check_contains "Case 12: history still in the toc"   '<a href="#document-history">Document history</a>' "$work/hist.html"

# --- Case 11a: script-injection vectors are neutralized ---------------------
# design.html is emailed and opened in a browser, and design docs absorb pasted content.
cat >"$work/xss.md" <<'EOF'
# X

<a href="javascript:alert(1)">click</a>

<span onclick="alert(2)">hover</span>

<strong style="color: #27ae60" onmouseover="alert(3)">badge</strong>

[label](javascript:alert%281%29)

[safe](https://example.com) and [anchor](#section) and [rel](./other.md)
EOF
python3 "$SCRIPT" "$work/xss.md" -o "$work/xss.html" >/dev/null
check_absent "Case 11a: no javascript: url" "javascript:alert(1)" "$work/xss.html"
check_absent "Case 11a: no encoded javascript: link" 'href="javascript' "$work/xss.html"
check_absent "Case 11a: no onclick handler" "onclick" "$work/xss.html"
check_absent "Case 11a: no onmouseover handler" "onmouseover" "$work/xss.html"
check_contains "Case 11a: badge style still allowed" 'style="color: #27ae60"' "$work/xss.html"
check_contains "Case 11a: safe https link kept" 'href="https://example.com"' "$work/xss.html"
check_contains "Case 11a: fragment link kept" 'href="#section"' "$work/xss.html"
check_contains "Case 11a: relative link kept" 'href="./other.md"' "$work/xss.html"

# --- Case 11b: a `----` line does not falsely close front matter ------------
printf -- '---\ntitle: T\n----\n\nBody text.\n' >"$work/fm4.md"
python3 "$SCRIPT" "$work/fm4.md" -o "$work/fm4.html" >/dev/null
check_absent "Case 11b: no stray dash paragraph" "<p>-</p>" "$work/fm4.html"

# --- Case 11c: leading-indented nested list emits balanced markup ----------
printf -- '# L\n\n  - only\n    - deeper\n' >"$work/li.md"
python3 "$SCRIPT" "$work/li.md" -o "$work/li.html" >/dev/null
li_open=$(grep -o "<li>" "$work/li.html" | wc -l | tr -d ' ')
li_close=$(grep -o "</li>" "$work/li.html" | wc -l | tr -d ' ')
check "Case 11c: <li> tags balanced" "$li_open" "$li_close"
ul_open=$(grep -o "<ul>" "$work/li.html" | wc -l | tr -d ' ')
ul_close=$(grep -o "</ul>" "$work/li.html" | wc -l | tr -d ' ')
check "Case 11c: <ul> tags balanced" "$ul_open" "$ul_close"

# --- Case 11d: soft-wrapped lines join into one paragraph ------------------
printf -- '# W\n\nThis is line one\nand line two continues.\n' >"$work/wrap.md"
python3 "$SCRIPT" "$work/wrap.md" -o "$work/wrap.html" >/dev/null
check_contains "Case 11d: soft wrap joined" "<p>This is line one and line two continues.</p>" "$work/wrap.html"

# --- Case 11: missing source file exits non-zero ----------------------------
python3 "$SCRIPT" "$work/does-not-exist.md" -o "$work/x.html" >/dev/null 2>&1
check "Case 11: missing input exits 1" "1" "$?"

# --- Case 12a: the shipped template is standalone markdown -----------------
# design.md is sent to people as a file; a link to a skill reference is a dead path for them.
check_absent "Case 12a: no skill-file link in template" "review-process.md" "$SCRIPT_DIR/../references/template.md"
check_absent "Case 12a: no guidance link in template" "section-guidance.md" "$SCRIPT_DIR/../references/template.md"
check_absent "Case 12a: no sample mermaid fence in template" '```mermaid' "$SCRIPT_DIR/../references/template.md"
check_contains "Case 12a: SELECTED badge example present" 'textbf{SELECTED}' "$SCRIPT_DIR/../references/template.md"

# --- Case 12: the real template renders without error -----------------------
python3 "$SCRIPT" "$SCRIPT_DIR/../references/template.md" -o "$work/tpl.html" >/dev/null 2>&1
check "Case 12: shipped template renders" "0" "$?"
check_contains "Case 12: open question highlighted" 'class="open-question"' "$work/tpl.html"
tpl_bytes=$(wc -c <"$work/tpl.html" | tr -d ' ')
check "Case 12: full template renders diagram-free and small" "small" \
  "$([ "$tpl_bytes" -lt 130000 ] && echo small || echo "large:$tpl_bytes")"

# --- Case 13: the review-annotation layer ----------------------------------
# Reviewers get only this file, so the whole annotation runtime must be inside it.
check_contains "Case 13: runtime config inlined" "window.__DESIGN_ANNOTATE__" "$work/tpl.html"
check_contains "Case 13: comment store present" 'id="design-comments"' "$work/tpl.html"
check_contains "Case 13: annotation styles inlined" ".anno-panel" "$work/tpl.html"
check_absent "Case 13: no external script src" "<script src" "$work/tpl.html"
check_contains "Case 13: author baked at render time" '"author"' "$work/tpl.html"

# --- Case 14: --no-annotate produces a clean reading copy -------------------
python3 "$SCRIPT" "$SCRIPT_DIR/../references/template.md" -o "$work/clean.html" --no-annotate >/dev/null
check_absent "Case 14: no runtime when disabled" "__DESIGN_ANNOTATE__" "$work/clean.html"
clean_bytes=$(wc -c <"$work/clean.html" | tr -d ' ')
check "Case 14: clean copy is much smaller" "small" \
  "$([ "$clean_bytes" -lt 30000 ] && echo small || echo "large:$clean_bytes")"

# --- Case 15: comments survive a re-render ----------------------------------
# A reviewer's notes must not be destroyed by regenerating the HTML from the markdown.
python3 - "$work/tpl.html" <<'PYEOF'
import json, re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
comments = [{"id": "c-test", "author": "Yossi Cohen (Product)", "created": "2026-08-30T10:00:00Z",
             "updated": "2026-08-30T10:00:00Z", "status": "open",
             "anchor": {"quote": "Security", "prefix": "", "suffix": "", "section": "security"},
             "body": "Round trip check.", "replies": []}]
payload = json.dumps(comments).replace("</", "<\\/")
text = re.sub(r'(<script type="application/json" id="design-comments">)(.*?)(</script>)',
              lambda m: m.group(1) + payload + m.group(3), text, flags=re.DOTALL)
path.write_text(text)
PYEOF
python3 "$SCRIPT" "$SCRIPT_DIR/../references/template.md" -o "$work/tpl.html" >/dev/null 2>&1
check_contains "Case 15: comment survived re-render" "Round trip check." "$work/tpl.html"
check_contains "Case 15: author survived re-render" "Yossi Cohen (Product)" "$work/tpl.html"

READER="$SCRIPT_DIR/read_design_comments.py"
reader_out=$(python3 "$READER" "$work/tpl.html" --status open 2>&1)
check "Case 15: reader extracts the comment" "yes" \
  "$(printf '%s' "$reader_out" | grep -q "Round trip check." && echo yes || echo no)"
check "Case 15: reader reports the section" "yes" \
  "$(printf '%s' "$reader_out" | grep -q "#security" && echo yes || echo no)"

# --- Case 16: mermaid blocks are validated before the file is written --------
# An invalid diagram renders a red "Syntax error in text" bomb that is invisible until a human
# opens the HTML, so the renderer must refuse to write instead. Skipped without node.
if command -v node >/dev/null 2>&1; then
  cat > "$work/badmermaid.md" <<'EOF'
---
title: Bad Diagram
---
# Bad Diagram
```mermaid
flowchart LR
    A --> B
    B -- yes --> |"double label"| C
```
EOF
  bad_out=$(python3 "$SCRIPT" "$work/badmermaid.md" -o "$work/badmermaid.html" 2>&1)
  check "Case 16: invalid diagram exits non-zero" "1" "$?"
  check "Case 16: no file written for an invalid diagram" "no"     "$([ -f "$work/badmermaid.html" ] && echo yes || echo no)"
  check "Case 16: the parse error is reported" "yes"     "$(printf '%s' "$bad_out" | grep -q "failed to parse" && echo yes || echo no)"

  cat > "$work/goodmermaid.md" <<'EOF'
---
title: Good Diagram
---
# Good Diagram
```mermaid
flowchart LR
    A -->|"yes · Product to DCP"| B
    B -.->|"response only"| A
```
EOF
  python3 "$SCRIPT" "$work/goodmermaid.md" -o "$work/goodmermaid.html" >/dev/null 2>&1
  check "Case 16: a valid diagram still renders" "0" "$?"
fi

cleanup "$work"

printf '\n%s passed, %s failed\n' "$pass_count" "$failures"
[ "$failures" -eq 0 ] || exit 1

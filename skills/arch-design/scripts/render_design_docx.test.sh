#!/usr/bin/env bash
# Tests for render_design_docx.py — design.md -> a formatted design.docx.
#
# The load-bearing case is Case 4: the docx template is full of <angle-bracket> placeholder
# prompts, and a permissive HTML-tag strip silently eats them — producing empty headings and blank
# sections in the Word file that goes to product. Both renderers share one tag allowlist for this
# reason; this case fails if the docx side ever drifts off it.
#
# Case 6 guards the other easy regression: the template's styles must survive, because reusing them
# is the entire reason the export fills a template instead of building a document from scratch.
#
# Run: bash render_design_docx.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render_design_docx.py"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_PYTHON="$SKILL_ROOT/.venv/bin/python"

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

# Global CLAUDE.md forbids rm for deletions; use trash when present, otherwise leave the
# mktemp directory for the OS to reap.
cleanup() {
  if command -v trash >/dev/null 2>&1; then
    trash "$1" >/dev/null 2>&1
  fi
}

# docx_query <file> <python-expression-over-`d`> — prints the result.
docx_query() {
  "$VENV_PYTHON" -c "
import sys, docx
d = docx.Document(sys.argv[1])
print($2)
" "$1"
}

work=$(mktemp -d)

cat >"$work/design.md" <<'EOF'
---
title: Host Config Compliance
status: In review
owner: Yehoda
team: Platform
jira: PROJ-1234
---

# Host Config Compliance

---

## Document history

| Date | Description of the document change | By whom | Comments |
|------|------------------------------------|---------|----------|
| 2026-08-30 | Initial draft | Yehoda | |

## Detailed Requirements (Customer-Facing)

- **R1:** Run compliance on VM configurations.
- **R2:** Create a finding on violation.

<What exists today and why it is not enough.>

### Design Alternatives

$\color{green}\textbf{DECISION}$ <strong style="color: #27ae60"><ins>**Decision:** use getResource</ins></strong>
EOF

python3 "$SCRIPT" "$work/design.md" -o "$work/design.docx" >/dev/null 2>&1
check "Case 1: exporter succeeds" "0" "$?"
check "Case 1: output file exists" "yes" "$([ -f "$work/design.docx" ] && echo yes || echo no)"

# --- Case 2: front matter becomes the title block ---------------------------
check "Case 2: title paragraph" "Host Config Compliance" \
  "$(docx_query "$work/design.docx" "d.paragraphs[0].text")"
check "Case 2: title uses Title style" "Title" \
  "$(docx_query "$work/design.docx" "d.paragraphs[0].style.name")"
check "Case 2: metadata line carries owner and jira" "True" \
  "$(docx_query "$work/design.docx" "'Yehoda' in d.paragraphs[1].text and 'PROJ-1234' in d.paragraphs[1].text")"

# --- Case 3: the H1 duplicating the front-matter title is suppressed --------
check "Case 3: no duplicate H1" "1" \
  "$(docx_query "$work/design.docx" "sum(1 for p in d.paragraphs if p.text == 'Host Config Compliance')")"

# --- Case 4: angle-bracket placeholders survive -----------------------------
# Regression guard: a permissive tag strip empties these out.
check "Case 4: placeholder text preserved" "True" \
  "$(docx_query "$work/design.docx" "any('What exists today' in p.text for p in d.paragraphs)")"
check "Case 4: no empty headings" "0" \
  "$(docx_query "$work/design.docx" "sum(1 for p in d.paragraphs if p.style.name.startswith('Heading') and not p.text.strip())")"

# --- Case 5: tables are rebuilt with their headers --------------------------
check "Case 5: one real table" "1" "$(docx_query "$work/design.docx" "len(d.tables)")"
check "Case 5: table header row" "Date" \
  "$(docx_query "$work/design.docx" "d.tables[0].rows[0].cells[0].text")"
check "Case 5: table body row" "Yehoda" \
  "$(docx_query "$work/design.docx" "d.tables[0].rows[1].cells[2].text")"

# --- Case 6: docx template styles are reused ------------------------------
check "Case 6: heading styles applied" "True" \
  "$(docx_query "$work/design.docx" "any(p.style.name == 'Heading 1' for p in d.paragraphs)")"
check "Case 6: template styles present" "True" \
  "$(docx_query "$work/design.docx" "'List Paragraph' in [s.name for s in d.styles]")"

# --- Case 7: markdown decoration is reduced to readable text ----------------
check "Case 7: bold markers stripped" "True" \
  "$(docx_query "$work/design.docx" "any(p.text.strip().startswith('• R1:') for p in d.paragraphs)")"
check "Case 7: latex badge becomes a label" "True" \
  "$(docx_query "$work/design.docx" "any('[DECISION]' in p.text for p in d.paragraphs)")"
check "Case 7: no raw html left" "True" \
  "$(docx_query "$work/design.docx" "all('<strong' not in p.text and '<ins>' not in p.text for p in d.paragraphs)")"

# --- Case 8: horizontal rules do not leak in as literal text ----------------
check "Case 8: no literal --- paragraph" "0" \
  "$(docx_query "$work/design.docx" "sum(1 for p in d.paragraphs if p.text.strip() == '---')")"

# --- Case 8a: soft-wrapped lines join, matching the HTML renderer ----------
# Emitting one Word paragraph per source line fragments spacing and misplaces track-changes.
printf -- '---\ntitle: W\n---\n\nThis is line one\nand line two continues.\n\nSecond para.\n' >"$work/wrap.md"
python3 "$SCRIPT" "$work/wrap.md" -o "$work/wrap.docx" >/dev/null
check "Case 8a: wrapped lines become one paragraph" "True" \
  "$(docx_query "$work/wrap.docx" "any(p.text == 'This is line one and line two continues.' for p in d.paragraphs)")"
check "Case 8a: separate paragraph stays separate" "True" \
  "$(docx_query "$work/wrap.docx" "any(p.text == 'Second para.' for p in d.paragraphs)")"

# --- Case 8b: a `----` line does not falsely close front matter ------------
printf -- '---\ntitle: T\n----\n\nBody text.\n' >"$work/fm4.md"
python3 "$SCRIPT" "$work/fm4.md" -o "$work/fm4.docx" >/dev/null
check "Case 8b: no stray dash paragraph" "0" \
  "$(docx_query "$work/fm4.docx" "sum(1 for p in d.paragraphs if p.text.strip() == '-')")"

# --- Case 9: missing source file exits non-zero -----------------------------
python3 "$SCRIPT" "$work/missing.md" -o "$work/x.docx" >/dev/null 2>&1
check "Case 9: missing input exits 1" "1" "$?"

# --- Case 10: the shipped template exports without error --------------------
python3 "$SCRIPT" "$SCRIPT_DIR/../references/template.md" -o "$work/tpl.docx" >/dev/null 2>&1
check "Case 10: shipped template exports" "0" "$?"
check "Case 10: approvals table has the three fixed areas" "True" \
  "$(docx_query "$work/tpl.docx" "any(t.rows[0].cells[0].text == 'Area' and len(t.rows) == 4 for t in d.tables)")"

cleanup "$work"

printf '\n%s passed, %s failed\n' "$pass_count" "$failures"
[ "$failures" -eq 0 ] || exit 1

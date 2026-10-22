#!/usr/bin/env bash
# Tests for extract_design_text.py — design files or folders -> one Markdown text stream.
#
# Run: bash extract_design_text.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/extract_design_text.py"
WORK="$(mktemp -d)"
trap 'trash "$WORK" 2>/dev/null || true' EXIT

failures=0
pass_count=0

check_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then
    pass_count=$((pass_count + 1))
    return
  fi
  printf 'FAIL: %s\n  missing: %s\n' "$label" "$needle" >&2
  failures=$((failures + 1))
}

check_absent() {
  local label="$1" needle="$2" file="$3"
  if ! grep -qF -- "$needle" "$file"; then
    pass_count=$((pass_count + 1))
    return
  fi
  printf 'FAIL: %s\n  unexpected: %s\n' "$label" "$needle" >&2
  failures=$((failures + 1))
}

check_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass_count=$((pass_count + 1))
    return
  fi
  printf 'FAIL: %s\n  expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
  failures=$((failures + 1))
}

mkdir -p "$WORK/arch" "$WORK/plain" "$WORK/arch/.hidden"

cat > "$WORK/arch/design.md" <<'EOF'
# Cache Layer

> **Maintenance:** This file is written and updated with the `arch-design` skill.

## Detailed Requirements (Customer-Facing)

- R1: Reads return in under 50 ms.
EOF

cat > "$WORK/arch/design.html" <<'EOF'
<html><head><meta charset="utf-8"><title>Cache Layer</title><style>body{}</style></head>
<body><nav class="toc"><a href="#x">Table of contents entry</a></nav>
<h1>Cache Layer copy</h1><p>HTML copy text</p>
<div class="anno-panel">Review panel chrome</div>
<script type="application/json" id="design-comments">[{"author":"Dana","status":"open","body":"What evicts entries?","anchor":{"section":"detailed-requirements","quote":"Reads return"}}]</script>
</body></html>
EOF

cat > "$WORK/arch/.hidden/ignored.md" <<'EOF'
Hidden folder text
EOF

cat > "$WORK/plain/proposal.html" <<'EOF'
<html><head><meta charset="utf-8"><script>var secret = 1;</script></head>
<body><h2>Queue Proposal</h2><p>Use one queue per tenant.</p>
<table><tr><th>Option</th><th>Cost</th></tr><tr><td>SQS</td><td>Low</td></tr></table></body></html>
EOF

python3 - "$WORK/plain/spec.docx" <<'EOF'
import sys, zipfile
w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
document = (
    f'<w:document {w}><w:body>'
    '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Storage Spec</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>Rows live in Postgres.</w:t></w:r></w:p>'
    '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>Owner</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    '</w:body></w:document>'
)
comments = (
    f'<w:comments {w}><w:comment w:id="0" w:author="Lior" w:date="2026-10-01T00:00:00Z">'
    '<w:p><w:r><w:t>Who owns backups?</w:t></w:r></w:p></w:comment></w:comments>'
)
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("word/document.xml", document)
    archive.writestr("word/comments.xml", comments)
EOF

# Case 1: an arch-design folder reads the markdown as source and only comments from the HTML.
python3 "$SCRIPT" "$WORK/arch" > "$WORK/out1.md"
check_contains "case 1: md text" "R1: Reads return in under 50 ms." "$WORK/out1.md"
check_contains "case 1: origin" "| md | source | arch-design |" "$WORK/out1.md"
check_contains "case 1: html role" "| html | comments only |" "$WORK/out1.md"
check_absent "case 1: html copy dropped" "HTML copy text" "$WORK/out1.md"
check_contains "case 1: embedded comment" '**Dana** (open) `#detailed-requirements` on "Reads return": What evicts entries?' "$WORK/out1.md"
check_absent "case 1: hidden folder skipped" "Hidden folder text" "$WORK/out1.md"

# Case 2: a standalone HTML keeps headings and tables, drops scripts, the TOC and review chrome.
python3 "$SCRIPT" "$WORK/plain/proposal.html" > "$WORK/out2.md"
check_contains "case 2: heading" "## Queue Proposal" "$WORK/out2.md"
check_contains "case 2: table row" "| SQS | Low |" "$WORK/out2.md"
check_contains "case 2: origin" "| generic |" "$WORK/out2.md"
check_absent "case 2: script dropped" "secret" "$WORK/out2.md"
python3 "$SCRIPT" "$WORK/arch/design.html" > "$WORK/out2b.md"
check_absent "case 2: toc dropped" "Table of contents entry" "$WORK/out2b.md"
check_absent "case 2: review chrome dropped" "Review panel chrome" "$WORK/out2b.md"
check_contains "case 2: lone html is source" "HTML copy text" "$WORK/out2b.md"

# Case 3: a .docx keeps headings and tables and lists Word comments.
python3 "$SCRIPT" "$WORK/plain/spec.docx" > "$WORK/out3.md"
check_contains "case 3: heading" "## Storage Spec" "$WORK/out3.md"
check_contains "case 3: paragraph" "Rows live in Postgres." "$WORK/out3.md"
check_contains "case 3: table" "| Table | Owner |" "$WORK/out3.md"
check_contains "case 3: comment" "**Lior** (open): Who owns backups?" "$WORK/out3.md"

# Case 4: --inventory prints only the table.
python3 "$SCRIPT" "$WORK/plain" --inventory > "$WORK/out4.md"
check_contains "case 4: lists docx" "spec.docx" "$WORK/out4.md"
check_absent "case 4: no text" "Rows live in Postgres." "$WORK/out4.md"

# Case 5: unsupported, missing and corrupt inputs fail with exit 1.
echo "x" > "$WORK/notes.txt"
python3 "$SCRIPT" "$WORK/notes.txt" > /dev/null 2>&1
check_exit "case 5: unsupported type" 1 $?
python3 "$SCRIPT" "$WORK/missing.md" > /dev/null 2>&1
check_exit "case 5: missing path" 1 $?
echo "not a zip" > "$WORK/broken.docx"
python3 "$SCRIPT" "$WORK/broken.docx" > /dev/null 2>&1
check_exit "case 5: corrupt docx" 1 $?

echo "extract_design_text: $pass_count passed, $failures failed"
[ "$failures" -eq 0 ]

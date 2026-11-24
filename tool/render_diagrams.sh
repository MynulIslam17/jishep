#!/usr/bin/env bash
# Renders every ```mermaid block in docs/diagrams/*.md (and APP_FLOW.md) to
# docs/diagrams/rendered/<file>_<n>.svg and fails on the first syntax error.
# Uses the installed Google Chrome (no Chromium download). Offline after the
# first `npx` install of @mermaid-js/mermaid-cli.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
OUT=docs/diagrams/rendered; mkdir -p "$OUT"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
printf '{"executablePath":"%s","args":["--no-sandbox"]}' "$CHROME" > "$WORK/pp.json"
python3 - "$WORK" <<'PY'
import re, sys, glob, os
w = sys.argv[1]
for f in sorted(glob.glob('docs/diagrams/[0-9]*.md')) + ['docs/APP_FLOW.md']:
    for i, b in enumerate(re.findall(r'```mermaid\n(.*?)```', open(f).read(), re.S)):
        open(f"{w}/{os.path.basename(f)[:-3]}_{i+1}.mmd", 'w').write(b)
PY
n=0
for f in "$WORK"/*.mmd; do
  name=$(basename "$f" .mmd)
  PUPPETEER_SKIP_DOWNLOAD=1 npx -y @mermaid-js/mermaid-cli@11.4.2 -q -p "$WORK/pp.json" -i "$f" -o "$OUT/$name.svg"
  if grep -qi "syntax error" "$OUT/$name.svg"; then echo "syntax error in $name" >&2; exit 1; fi
  n=$((n+1))
done
echo "rendered $n diagrams → $OUT"

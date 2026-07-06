#!/usr/bin/env bash
# repomap.sh — generate a compact codebase map for small-context local models.
#
# Primary path: repomix (tree-sitter --compress → signatures only, secretlint
# security check, token budget guard). Falls back to a zero-dependency
# grep-based generator when node/npx is unavailable.
#
# Output: .agents/repomap.md (budgeted ~8k tokens via repomix tokenBudget,
# or 16 KB cap in fallback mode). Run from the repo root of the target project.
#
# Modes:
#   repomap.sh                 always regenerate
#   repomap.sh --if-stale      regenerate only if HEAD moved since last map AND the
#                              project opted in (repomix.config.json or existing map).
#                              Silent no-op otherwise — safe to call from hooks.
#   repomap.sh --install-hook  wire post-commit/post-merge/post-checkout git hooks
#                              so the map auto-refreshes (covers OpenCode sessions too)
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "repomap: not inside a git repo" >&2
  exit 1
fi

OUT=".agents/repomap.md"
HEAD_MARK=".agents/.repomap-head"
MODE="${1:-}"

if [ "$MODE" = "--install-hook" ]; then
  hookdir="$(git rev-parse --git-path hooks)"
  for h in post-commit post-merge post-checkout; do
    hook="$hookdir/$h"
    if [ -f "$hook" ] && ! grep -q repomap "$hook"; then
      echo "repomap: $hook exists — append manually: repomap --if-stale >/dev/null 2>&1 || true" >&2
      continue
    fi
    printf '#!/bin/sh\ncommand -v repomap >/dev/null 2>&1 && repomap --if-stale >/dev/null 2>&1 || true\n' > "$hook"
    chmod +x "$hook"
    echo "installed $h hook"
  done
  exit 0
fi

if [ "$MODE" = "--if-stale" ]; then
  # Only act in repos that opted in — never seed config into arbitrary repos.
  if [ ! -f repomix.config.json ] && [ ! -f "$OUT" ]; then
    exit 0
  fi
  head_now="$(git rev-parse HEAD 2>/dev/null || echo none)"
  if [ -f "$OUT" ] && [ -f "$HEAD_MARK" ] && [ "$(cat "$HEAD_MARK")" = "$head_now" ]; then
    exit 0  # fresh — nothing to do
  fi
fi

mkdir -p .agents

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"

# ---------------------------------------------------------------- repomix path
run_repomix() {
  # Config-file driven: repomix picks up ./repomix.config.json automatically.
  # Seed the tuned template on first run (edit `include` per repo afterwards).
  if [ ! -f repomix.config.json ]; then
    cp "$TEMPLATE_DIR/repomix.config.json" repomix.config.json
    echo "repomap: seeded repomix.config.json (tune the 'include' globs for this repo)"
  fi

  local rc=0
  if command -v repomix >/dev/null 2>&1; then
    repomix || rc=$?
  else
    npx -y repomix || rc=$?
  fi

  # tokenBudget exceeded -> non-zero exit, but output is still written.
  if [ "$rc" -ne 0 ]; then
    echo "repomap: WARNING — over the 8k-token budget (or repomix error, rc=$rc)." >&2
    echo "         Tighten 'include'/'ignore.customPatterns' in repomix.config.json." >&2
  fi
}

# ------------------------------------------------------- grep fallback (no node)
run_fallback() {
  local MAX_BYTES="${REPOMAP_MAX_BYTES:-16000}"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  {
    echo "# Repo map — generated $(date +%F). Regenerate with scripts/repomap.sh. Do not edit."
    echo
    echo "## Directories"
    echo '```'
    git ls-files \
      | xargs -n1 dirname 2>/dev/null \
      | sort -u \
      | awk -F/ 'NF<=3 && $1 != "." && $0 !~ /^\.(agents|github|next|vercel)/' \
      | head -80
    echo '```'
    echo

    echo "## Routes"
    git ls-files \
      | grep -E '^(src/)?(app/([^/]+/)*(page|route|layout|loading|error)\.[tj]sx?|pages/.+\.[tj]sx?)$' \
      | grep -vE '_app|_document' \
      | sed 's/^/- /' \
      | head -60
    echo

    echo "## Exports (file: symbols)"
    git ls-files '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' \
      | grep -vE '\.(test|spec|stories)\.|\.d\.ts$|(^|/)(node_modules|dist|build|\.next)/' \
      | while IFS= read -r f; do
          syms="$(grep -hoE 'export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|const|class|type|interface|enum)[[:space:]]+[A-Za-z0-9_]+' "$f" 2>/dev/null \
            | awk '{print $NF}' | sort -u | paste -sd, - | sed 's/,/, /g' || true)"
          [ -n "$syms" ] && printf -- '- %s: %s\n' "$f" "$syms"
        done | head -220
    echo

    if [ -f package.json ] && command -v jq >/dev/null 2>&1; then
      echo "## Dependencies"
      jq -r '(.dependencies // {}) | keys | join(", ")' package.json | sed 's/^/- deps: /'
      jq -r '(.devDependencies // {}) | keys | join(", ")' package.json | sed 's/^/- dev: /'
    fi
  } > "$tmp"

  head -c "$MAX_BYTES" "$tmp" > "$OUT"
}

# ------------------------------------------------------------------------ main
if command -v repomix >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  run_repomix
else
  echo "repomap: node/npx not found — using grep fallback (weaker: TS/JS exports only)" >&2
  run_fallback
fi

if [ -f "$OUT" ]; then
  git rev-parse HEAD > "$HEAD_MARK" 2>/dev/null || true
  bytes="$(wc -c < "$OUT" | tr -d ' ')"
  echo "wrote $OUT (${bytes} bytes ≈ $((bytes / 4)) tokens)"
else
  echo "repomap: no output produced" >&2
  exit 1
fi

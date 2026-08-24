#!/usr/bin/env bash
# run-pmd.sh — PMD Apex static analysis (RULES.md #1 merge gate)
#
# Downloads PMD into ./tools on first run, then analyzes force-app with
# config/pmd-ruleset.xml. Non-zero exit = violations found = CI fails.
#
# Env overrides:
#   PMD_VERSION   pinned PMD release (default 7.7.0)
#   PMD_DIR       install location (default ./tools/pmd)
set -euo pipefail

PMD_VERSION="${PMD_VERSION:-7.7.0}"
PMD_DIR="${PMD_DIR:-tools/pmd}"
RULESET="config/pmd-ruleset.xml"
SRC="force-app/main/default"
REPORT="pmd-report.txt"

if [ ! -x "$PMD_DIR/bin/pmd" ]; then
  echo "PMD not found — downloading v$PMD_VERSION ..."
  mkdir -p "$(dirname "$PMD_DIR")"
  URL="https://github.com/pmd/pmd/releases/download/pmd_releases%2F$PMD_VERSION/pmd-dist-$PMD_VERSION-bin.zip"
  TMPZIP="$(mktemp -t pmd.XXXXXX).zip"
  curl -sSL "$URL" -o "$TMPZIP"
  unzip -q -o "$TMPZIP" -d "$(dirname "$PMD_DIR")"
  rm -f "$TMPZIP"
  mv "$(dirname "$PMD_DIR")/pmd-bin-$PMD_VERSION" "$PMD_DIR"
fi

if [ ! -d "$SRC" ]; then
  echo "Source directory $SRC not found — nothing to analyze."
  exit 0
fi

echo "Running PMD $("$PMD_DIR/bin/pmd" --version) on $SRC ..."
set +e
"$PMD_DIR/bin/pmd" check \
  --dir "$SRC" \
  --rulesets "$RULESET" \
  --format text \
  --report-file "$REPORT"
STATUS=$?
set -e

VIOLATIONS=$(grep -c 'Warning:' "$REPORT" || true)
if [ "$STATUS" -ne 0 ]; then
  echo ""
  echo "PMD FAILED: $VIOLATIONS violation(s) found. Full report: $REPORT"
  cat "$REPORT"
  exit 1
fi

echo "PMD passed: no violations."

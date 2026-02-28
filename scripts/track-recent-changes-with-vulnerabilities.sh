#!/usr/bin/env bash
set -euo pipefail

SINCE_ARG="${1:-14 days ago}"
REPORT_DIR="${2:-reports}"
TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
REPORT_FILE="$REPORT_DIR/change-vulnerability-report-$TIMESTAMP.md"

mkdir -p "$REPORT_DIR"

{
  echo "# Change and Vulnerability Report"
  echo
  echo "- Generated (UTC): $(date -u +'%Y-%m-%d %H:%M:%S')"
  echo "- Change window: last commits since '$SINCE_ARG'"
  echo
  echo "## Recent changes"
  echo
  if git log --since="$SINCE_ARG" --pretty=format:'- %h %ad %s (%an)' --date=short | sed '/^$/d' | head -n 50; then
    :
  else
    echo "- No commits found in the selected window."
  fi
  echo
  echo "## Vulnerability summary"
  echo
  AUDIT_JSON="$(mktemp)"
  if npm audit --json >"$AUDIT_JSON" 2>/dev/null; then
    :
  else
    # npm audit exits non-zero when vulnerabilities are found, so parse output anyway.
    npm audit --json >"$AUDIT_JSON" || true
  fi

  node -e '
const fs = require("fs");
const p = process.argv[1];
const raw = fs.readFileSync(p, "utf8");
const data = JSON.parse(raw);
const v = data.metadata?.vulnerabilities || {};
const total = Object.values(v).reduce((sum, n) => sum + (typeof n === "number" ? n : 0), 0);
console.log(`- Total vulnerabilities: ${total}`);
console.log(`- Critical: ${v.critical || 0}`);
console.log(`- High: ${v.high || 0}`);
console.log(`- Moderate: ${v.moderate || 0}`);
console.log(`- Low: ${v.low || 0}`);
console.log(`- Info: ${v.info || 0}`);
' "$AUDIT_JSON"

  echo
  echo "## Top vulnerable packages"
  echo
  node -e '
const fs = require("fs");
const p = process.argv[1];
const raw = fs.readFileSync(p, "utf8");
const data = JSON.parse(raw);
const advisories = data.vulnerabilities || {};
const entries = Object.entries(advisories)
  .map(([name, vuln]) => ({
    name,
    severity: vuln.severity || "unknown",
    viaCount: Array.isArray(vuln.via) ? vuln.via.length : 0,
    fixAvailable: vuln.fixAvailable ? "yes" : "no"
  }))
  .sort((a, b) => b.viaCount - a.viaCount)
  .slice(0, 15);
if (!entries.length) {
  console.log("- No vulnerable packages reported by npm audit.");
} else {
  for (const e of entries) {
    console.log(`- ${e.name}: severity=${e.severity}, via=${e.viaCount}, fixAvailable=${e.fixAvailable}`);
  }
}
' "$AUDIT_JSON"

  rm -f "$AUDIT_JSON"

  echo
  echo "## Suggested next actions"
  echo
  echo "- Run: npm audit fix"
  echo "- Review major-version updates manually before applying force fixes."
  echo "- Re-run this report after dependency updates to track trend over time."
} > "$REPORT_FILE"

echo "Report written to: $REPORT_FILE"

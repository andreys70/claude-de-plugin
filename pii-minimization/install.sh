#!/usr/bin/env bash
# PII Minimization plugin installer — sets up auto-load on every Claude session.
#
# Run once per machine (or after wiping ~/.claude):
#   bash /path/to/claude-de-plugins/pii-minimization/install.sh
#
# After this, every `claude` session auto-loads:
#   /pii-minimization:phase1       — Apply Phase 1 decrypt-on-read
#   /pii-minimization:phase2       — Apply Phase 2 encrypt-on-write
#   /pii-minimization:redshift-widen — Redshift column widening gate

set -euo pipefail

REPO_PLUGIN="$(cd "$(dirname "$0")" && pwd)"
MARKETPLACE="$HOME/.claude/pii-minimization-marketplace"
SETTINGS="$HOME/.claude/settings.json"

echo "📦 PII Minimization plugin installer"
echo "   Repo:        $REPO_PLUGIN"
echo "   Marketplace: $MARKETPLACE"
echo ""

# 1. Verify plugin files exist
for f in .claude-plugin/plugin.json commands/phase1.md commands/phase2.md agents/rda-bpp-engineer.md agents/quicketl-engineer.md; do
  if [ ! -e "$REPO_PLUGIN/$f" ]; then
    echo "❌ Missing: $REPO_PLUGIN/$f"
    echo "   Make sure you've cloned claude-de-plugins and this script is at <repo>/pii-minimization/install.sh"
    exit 1
  fi
done
echo "✅ Plugin files verified in repo"

# 2. Create marketplace directory structure
mkdir -p "$MARKETPLACE/.claude-plugin" "$MARKETPLACE/pii-minimization"

# 3. Write marketplace manifest
cat > "$MARKETPLACE/.claude-plugin/marketplace.json" <<JSON
{
  "name": "intuit-de-pii",
  "description": "Intuit Data Engineering — PII Minimization plugin",
  "owner": {
    "name": "$(git config user.name 2>/dev/null || echo "Engineer")",
    "email": "$(git config user.email 2>/dev/null || echo "")"
  },
  "plugins": [
    {
      "name": "pii-minimization",
      "source": "./pii-minimization",
      "description": "End-to-end IDPS encryption rollout: Phase 1 decrypt-on-read and Phase 2 encrypt-on-write across RDA BPP, QuickETL, SPP, Report Requestor, and Quickbase pipelines."
    }
  ]
}
JSON
echo "✅ Marketplace manifest written"

# 4. Symlink plugin subdirs from marketplace → git repo
for d in .claude-plugin agents commands skills; do
  rm -f "$MARKETPLACE/pii-minimization/$d"
  ln -s "$REPO_PLUGIN/$d" "$MARKETPLACE/pii-minimization/$d"
done
echo "✅ Plugin symlinks created"

# 5. Verify symlinks resolve
for d in .claude-plugin agents commands skills; do
  if [ ! -e "$MARKETPLACE/pii-minimization/$d" ]; then
    echo "❌ Broken symlink: $MARKETPLACE/pii-minimization/$d"
    exit 1
  fi
done
echo "✅ All symlinks resolve to real files"

# 6. Update ~/.claude/settings.json
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" "$MARKETPLACE" <<'PY'
import json, sys
settings_path, marketplace_path = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    s = json.load(f)

s.setdefault("extraKnownMarketplaces", {})
s["extraKnownMarketplaces"]["intuit-de-pii"] = {
    "source": {"source": "directory", "path": marketplace_path}
}

s.setdefault("enabledPlugins", {})
s["enabledPlugins"]["pii-minimization@intuit-de-pii"] = True

with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
print(f"✅ Updated {settings_path}: marketplace registered, plugin enabled for auto-load")
PY

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Verify with:"
echo "   claude plugin list    # should show pii-minimization@intuit-de-pii enabled"
echo ""
echo "Usage:"
echo "   /pii-minimization:phase1 FIND-773"
echo "   /pii-minimization:phase2 FIND-719"
echo "   /pii-minimization:redshift-widen FIND-699"
echo ""
echo "Required MCPs (connect before running):"
echo "   mcp__jira-mcp          — Jira read/write"
echo "   mcp__DAST-Orch         — BPP pipeline execution + GitHub"

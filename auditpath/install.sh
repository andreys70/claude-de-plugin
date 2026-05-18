#!/usr/bin/env bash
# AuditPath plugin installer — sets up auto-load on every Claude session.
#
# Run once per machine (or after wiping ~/.claude):
#   bash /path/to/quick-etl-pipeline-configs/auditpath/install.sh
#
# After this, every `claude` session auto-loads /auditpath:annotate and /auditpath:onboard.

set -euo pipefail

REPO_AUDITPATH="$(cd "$(dirname "$0")" && pwd)"
MARKETPLACE="$HOME/.claude/auditpath-marketplace"
SETTINGS="$HOME/.claude/settings.json"

echo "📦 AuditPath plugin installer"
echo "   Repo:        $REPO_AUDITPATH"
echo "   Marketplace: $MARKETPLACE"
echo ""

# 1. Verify repo has the plugin files
for f in .claude-plugin/plugin.json commands/annotate.md agents/code-annotator.md scripts/generate_annotation.py; do
  if [ ! -e "$REPO_AUDITPATH/$f" ]; then
    echo "❌ Missing: $REPO_AUDITPATH/$f"
    echo "   Make sure you've cloned quick-etl-pipeline-configs and this script is at <repo>/auditpath/install.sh"
    exit 1
  fi
done
echo "✅ Plugin files verified in repo"

# 2. Create the marketplace directory structure
mkdir -p "$MARKETPLACE/.claude-plugin" "$MARKETPLACE/auditpath"

# 3. Write the marketplace manifest
cat > "$MARKETPLACE/.claude-plugin/marketplace.json" <<JSON
{
  "name": "intuit-de-plugins",
  "description": "Intuit Data Engineering plugins (local marketplace for AuditPath)",
  "owner": {
    "name": "$(git config user.name 2>/dev/null || echo "Engineer")",
    "email": "$(git config user.email 2>/dev/null || echo "")"
  },
  "plugins": [
    {
      "name": "auditpath",
      "source": "./auditpath",
      "description": "End-to-end SOX pipeline onboarding plugin"
    }
  ]
}
JSON
echo "✅ Marketplace manifest written"

# 4. Symlink plugin subdirs from marketplace → git repo
for d in .claude-plugin agents commands scripts skills; do
  rm -f "$MARKETPLACE/auditpath/$d"
  ln -s "$REPO_AUDITPATH/$d" "$MARKETPLACE/auditpath/$d"
done
echo "✅ Plugin symlinks created"

# 5. Verify symlinks resolve
for d in .claude-plugin agents commands scripts skills; do
  if [ ! -e "$MARKETPLACE/auditpath/$d" ]; then
    echo "❌ Broken symlink: $MARKETPLACE/auditpath/$d"
    exit 1
  fi
done
echo "✅ All symlinks resolve to real files"

# 6. Update ~/.claude/settings.json — add the marketplace and enable the plugin
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" "$MARKETPLACE" <<'PY'
import json, sys
settings_path, marketplace_path = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    s = json.load(f)

# Register the marketplace if missing
s.setdefault("extraKnownMarketplaces", {})
s["extraKnownMarketplaces"]["intuit-de-plugins"] = {
    "source": {"source": "directory", "path": marketplace_path}
}

# Enable the plugin for auto-load
s.setdefault("enabledPlugins", {})
s["enabledPlugins"]["auditpath@intuit-de-plugins"] = True

with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
print(f"✅ Updated {settings_path}: marketplace registered, plugin enabled for auto-load")
PY

# 7. Make script executable
chmod +x "$REPO_AUDITPATH/scripts/generate_annotation.py"
echo "✅ Script marked executable"

# 8. Verify openpyxl is available (required by the script)
if ! python3 -c "import openpyxl" 2>/dev/null; then
  echo ""
  echo "⚠️  openpyxl is not installed. Run:"
  echo "     pip3 install openpyxl"
  echo "   (or it'll be auto-installed on first /auditpath:annotate run)"
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Verify with:"
echo "   claude plugin list                    # should show auditpath@intuit-de-plugins enabled"
echo "   claude                                # launch session, type /auditpath:annotate to see it"

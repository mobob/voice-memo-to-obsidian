#!/bin/zsh
#
# upgrade.sh
# Upgrades voice-memo-to-obsidian scripts without touching user config or prompts
#

set -e

SCRIPT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/voice-memo"
SCRIPTS_DIR="$CONFIG_DIR/scripts"

echo "========================================"
echo "  Voice Memo to Obsidian - Upgrade"
echo "========================================"
echo ""

# Check if installed
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "ERROR: Not installed. Run install.sh first."
    exit 1
fi

if [[ ! -f "$CONFIG_DIR/config" ]]; then
    echo "ERROR: Config not found. Run install.sh first."
    exit 1
fi

# Load config to get vault path
source "$CONFIG_DIR/config"

echo "Upgrading scripts..."
cp "$SCRIPT_DIR/scripts/voice-memo-to-obsidian.sh" "$SCRIPTS_DIR/"
cp "$SCRIPT_DIR/scripts/voice-memo-watcher.sh" "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR"/*.sh
echo "  ✓ Scripts updated"

echo ""
echo "========================================"
echo "  Upgrade Complete"
echo "========================================"
echo ""
echo "Updated:"
echo "  ✓ $SCRIPTS_DIR/voice-memo-to-obsidian.sh"
echo "  ✓ $SCRIPTS_DIR/voice-memo-watcher.sh"
echo ""
echo "Preserved (not modified):"
echo "  • $CONFIG_DIR/config"
echo "  • $OBSIDIAN_VAULT/Areas/Voice Memo Pipeline/*.md"
echo ""
echo "To update prompts manually, compare with samples in:"
echo "  $SCRIPT_DIR/prompts/"
echo ""

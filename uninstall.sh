#!/bin/zsh
#
# uninstall.sh
# Removes voice-memo-to-obsidian
#

CONFIG_DIR="$HOME/.config/voice-memo"

echo "========================================"
echo "  Voice Memo to Obsidian - Uninstaller"
echo "========================================"
echo ""

# Remove cron job
echo "Removing cron job..."
crontab -l 2>/dev/null | grep -v "voice-memo-watcher" | crontab - 2>/dev/null || true
echo "  ✓ Cron job removed"

# Remove config directory
if [[ -d "$CONFIG_DIR" ]]; then
    echo "Removing config directory..."
    rm -rf "$CONFIG_DIR"
    echo "  ✓ Removed: $CONFIG_DIR"
fi

echo ""
echo "========================================"
echo "  Uninstall Complete"
echo "========================================"
echo ""
echo "Note: Prompts and output notes in your Obsidian vault were NOT removed."
echo "Remove manually if desired:"
echo "  - Areas/Voice Memo Pipeline/"
echo "  - Daily/Babble/"
echo ""

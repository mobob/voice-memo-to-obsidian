#!/bin/zsh
#
# install.sh
# Installs voice-memo-to-obsidian
#

set -e

SCRIPT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/voice-memo"
SCRIPTS_DIR="$CONFIG_DIR/scripts"

echo "========================================"
echo "  Voice Memo to Obsidian - Installer"
echo "========================================"
echo ""

# Check dependencies
echo "Checking dependencies..."

if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found"
    echo "Install with: brew install ffmpeg"
    exit 1
fi
echo "  ✓ ffmpeg"

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq not found"
    echo "Install with: brew install jq"
    exit 1
fi
echo "  ✓ jq"

echo ""

# Check for existing installation
if [[ -f "$CONFIG_DIR/config" ]]; then
    echo "Existing installation detected."
    echo "Use upgrade.sh to update scripts without losing your config."
    echo ""
    read -r "CONTINUE?Reinstall anyway? This will overwrite your config. [y/N] "
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Aborted. Use upgrade.sh instead."
        exit 0
    fi
    echo ""
fi

# Get Obsidian vault path
echo "Enter the path to your Obsidian vault:"
echo "(e.g., ~/Documents/MyVault or /Users/you/Obsidian/MyVault)"
read -r "OBSIDIAN_VAULT_INPUT?> "

# Expand ~ if present
OBSIDIAN_VAULT="${OBSIDIAN_VAULT_INPUT/#\~/$HOME}"

if [[ ! -d "$OBSIDIAN_VAULT" ]]; then
    echo "ERROR: Directory not found: $OBSIDIAN_VAULT"
    exit 1
fi
echo "  ✓ Vault found: $OBSIDIAN_VAULT"
echo ""

# Get Gemini API key
echo "Enter your Gemini API key:"
echo "(Get one at: https://makersuite.google.com/app/apikey)"
read -r "GEMINI_API_KEY?> "

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "ERROR: API key required"
    exit 1
fi
echo "  ✓ API key received"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$CONFIG_DIR/processed"
echo "  ✓ $CONFIG_DIR"

# Copy scripts (always overwrite - these are upgradable)
echo "Installing scripts..."
cp "$SCRIPT_DIR/scripts/voice-memo-to-obsidian.sh" "$SCRIPTS_DIR/"
cp "$SCRIPT_DIR/scripts/voice-memo-watcher.sh" "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR"/*.sh
echo "  ✓ Scripts installed"

# Create config file (user-editable)
echo "Creating config..."
cat > "$CONFIG_DIR/config" << EOF
# Voice Memo to Obsidian Configuration
GEMINI_API_KEY="$GEMINI_API_KEY"
OBSIDIAN_VAULT="$OBSIDIAN_VAULT"

# Optional: change the Gemini model
# GEMINI_MODEL="gemini-2.5-flash"
EOF
echo "  ✓ Config created"

# Copy prompts to Obsidian vault (only if they don't exist - user-editable)
PROMPTS_DIR="$OBSIDIAN_VAULT/Areas/Voice Memo Pipeline"
echo "Installing prompts to Obsidian..."
mkdir -p "$PROMPTS_DIR"

if [[ ! -f "$PROMPTS_DIR/transcription-prompt.md" ]]; then
    cp "$SCRIPT_DIR/prompts/transcription-prompt.sample.md" "$PROMPTS_DIR/transcription-prompt.md"
    echo "  ✓ Created: transcription-prompt.md"
else
    echo "  • Skipped: transcription-prompt.md (already exists)"
fi

if [[ ! -f "$PROMPTS_DIR/analysis-prompt.md" ]]; then
    cp "$SCRIPT_DIR/prompts/analysis-prompt.sample.md" "$PROMPTS_DIR/analysis-prompt.md"
    echo "  ✓ Created: analysis-prompt.md"
else
    echo "  • Skipped: analysis-prompt.md (already exists)"
fi

# Create output directory in vault
mkdir -p "$OBSIDIAN_VAULT/Daily/Babble"
echo "  ✓ Output directory: Daily/Babble/"

# Setup cron job
echo ""
echo "Setting up cron job (runs every 2 minutes)..."

# Remove any existing voice-memo cron entries and add new one
CRON_CMD="*/2 * * * * /bin/zsh $SCRIPTS_DIR/voice-memo-watcher.sh >> $CONFIG_DIR/cron.log 2>&1"
(crontab -l 2>/dev/null | grep -v "voice-memo-watcher" ; echo "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; echo "$CRON_CMD") | crontab -
echo "  ✓ Cron job installed"

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "IMPORTANT: Grant Full Disk Access to cron"
echo ""
echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
echo "  2. Click + button"
echo "  3. Press Cmd+Shift+G and type: /usr/sbin/cron"
echo "  4. Select 'cron' and enable the toggle"
echo ""
echo "Files:"
echo ""
echo "  Upgradable (overwritten by upgrade.sh):"
echo "    $SCRIPTS_DIR/voice-memo-to-obsidian.sh"
echo "    $SCRIPTS_DIR/voice-memo-watcher.sh"
echo ""
echo "  User-editable (never overwritten):"
echo "    $CONFIG_DIR/config"
echo "    $PROMPTS_DIR/transcription-prompt.md"
echo "    $PROMPTS_DIR/analysis-prompt.md"
echo ""
echo "  Output:"
echo "    $OBSIDIAN_VAULT/Daily/Babble/"
echo ""
echo "Logs:"
echo "  tail -f $CONFIG_DIR/voice-memo.log"
echo ""
echo "To test manually:"
echo "  $SCRIPTS_DIR/voice-memo-watcher.sh"
echo ""

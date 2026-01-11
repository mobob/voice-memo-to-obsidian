#!/bin/zsh
#
# voice-memo-watcher.sh
# Polls for new Voice Memos and processes them
# Designed to run via cron every 2 minutes
#

SCRIPT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/voice-memo"
CONFIG_FILE="$CONFIG_DIR/config"
PROCESSOR="$SCRIPT_DIR/voice-memo-to-obsidian.sh"
PROCESSED_DIR="$CONFIG_DIR/processed"
LOG_FILE="$CONFIG_DIR/voice-memo.log"

# Voice Memos location (iCloud synced)
RECORDINGS_DIR="$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"

# How far back to look for new files (in minutes)
LOOKBACK_MINUTES=10

# Minimum file size to process (skip tiny/empty files)
MIN_FILE_SIZE=5000

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [watcher] $1" >> "$LOG_FILE"
}

log "=== Watcher triggered ==="
log "Checking directory: $RECORDINGS_DIR"

# Check if we can access the directory
if [[ ! -d "$RECORDINGS_DIR" ]]; then
    log "ERROR: Cannot access recordings dir"
    log "Check Full Disk Access permissions for /usr/sbin/cron"
    exit 1
fi

# Count total files
TOTAL_FILES=$(find "$RECORDINGS_DIR" -name "*.m4a" -type f 2>/dev/null | wc -l | tr -d ' ')
log "Total .m4a files in directory: $TOTAL_FILES"

# Find recent files
RECENT_FILES=$(find "$RECORDINGS_DIR" -name "*.m4a" -type f -mmin -${LOOKBACK_MINUTES} 2>/dev/null)
RECENT_COUNT=$(echo "$RECENT_FILES" | grep -c "m4a" || echo "0")
log "Files modified in last ${LOOKBACK_MINUTES} min: $RECENT_COUNT"

# Show newest file
NEWEST=$(find "$RECORDINGS_DIR" -name "*.m4a" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1)
if [[ -n "$NEWEST" ]]; then
    NEWEST_FILE=$(echo "$NEWEST" | cut -d' ' -f2-)
    NEWEST_NAME=$(basename "$NEWEST_FILE")
    NEWEST_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$NEWEST_FILE" 2>/dev/null)
    log "Newest file: $NEWEST_NAME (modified: $NEWEST_TIME)"
fi

# Process recent files
PROCESSED_COUNT=0
echo "$RECENT_FILES" | while read -r file; do
    [[ -z "$file" ]] && continue

    filename=$(basename "$file")
    marker="$PROCESSED_DIR/${filename}.done"

    # Skip if already processed
    if [[ -f "$marker" ]]; then
        log "  Skipping (already done): $filename"
        continue
    fi

    # Check file size
    filesize=$(stat -f%z "$file" 2>/dev/null || echo "0")
    if [[ "$filesize" -lt "$MIN_FILE_SIZE" ]]; then
        log "  Skipping (too small: ${filesize}b): $filename"
        continue
    fi

    log "  Processing: $filename ($filesize bytes)"
    "$PROCESSOR" "$file"
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
done

log "=== Watcher complete ==="

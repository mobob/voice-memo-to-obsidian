#!/bin/zsh
#
# voice-memo-to-obsidian.sh
# Transcribes voice memos using Gemini API and creates Obsidian notes
#

set -e

# Configuration - these are set by install.sh
CONFIG_DIR="$HOME/.config/voice-memo"
CONFIG_FILE="$CONFIG_DIR/config"
PROCESSED_DIR="$CONFIG_DIR/processed"
LOG_FILE="$CONFIG_DIR/voice-memo.log"

# Load config
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    echo "Run install.sh first"
    exit 1
fi
source "$CONFIG_FILE"

# Validate required config
if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "ERROR: GEMINI_API_KEY not set in config"
    exit 1
fi

if [[ -z "$OBSIDIAN_VAULT" ]]; then
    echo "ERROR: OBSIDIAN_VAULT not set in config"
    exit 1
fi

# Derived paths
VOICE_MEMOS_PATH="$OBSIDIAN_VAULT/Daily/Babble"
PROMPTS_DIR="$OBSIDIAN_VAULT/Areas/Voice Memo Pipeline"

# Gemini API settings
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
GEMINI_API_BASE="https://generativelanguage.googleapis.com"

# Find ffmpeg
if [[ -x "/opt/homebrew/bin/ffmpeg" ]]; then
    FFMPEG="/opt/homebrew/bin/ffmpeg"
elif [[ -x "/usr/local/bin/ffmpeg" ]]; then
    FFMPEG="/usr/local/bin/ffmpeg"
else
    FFMPEG=$(which ffmpeg 2>/dev/null || echo "")
fi

if [[ -z "$FFMPEG" ]]; then
    echo "ERROR: ffmpeg not found. Install with: brew install ffmpeg"
    exit 1
fi

# Create directories
mkdir -p "$PROCESSED_DIR" "$VOICE_MEMOS_PATH" "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for required argument
if [[ -z "$1" ]]; then
    log "ERROR: No input file provided"
    echo "Usage: $0 <path-to-m4a-file>"
    exit 1
fi

INPUT_FILE="$1"
FILENAME=$(basename "$INPUT_FILE")

# Skip if not an audio file
if [[ ! "$FILENAME" =~ \.(m4a|mp3|wav|aac)$ ]]; then
    log "Skipping non-audio file: $FILENAME"
    exit 0
fi

# Skip if already processed
PROCESSED_MARKER="$PROCESSED_DIR/${FILENAME}.done"
if [[ -f "$PROCESSED_MARKER" ]]; then
    log "Already processed: $FILENAME"
    exit 0
fi

log "Processing: $FILENAME"

# Convert to MP3 for API compatibility
TEMP_DIR=$(mktemp -d)
MP3_FILE="$TEMP_DIR/audio.mp3"
TEMP_INPUT="$TEMP_DIR/input.m4a"

# Copy input file to temp (avoids FDA issues with ffmpeg)
log "Copying to temp..."
if ! cp "$INPUT_FILE" "$TEMP_INPUT" 2>&1; then
    log "ERROR: Failed to copy input file"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log "Converting to MP3..."
FFMPEG_LOG="$TEMP_DIR/ffmpeg.log"
if ! "$FFMPEG" -i "$TEMP_INPUT" -codec:a libmp3lame -qscale:a 2 -y "$MP3_FILE" 2>"$FFMPEG_LOG"; then
    log "ERROR: ffmpeg failed"
    log "ERROR: $(cat "$FFMPEG_LOG" | tail -5)"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if [[ ! -f "$MP3_FILE" ]]; then
    log "ERROR: MP3 file not created"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Get file size for upload
FILE_SIZE=$(stat -f%z "$MP3_FILE")
log "Audio file size: $FILE_SIZE bytes"

# Step 1: Initialize resumable upload
log "Initializing Gemini upload..."
INIT_RESPONSE=$(curl -s -X POST \
    "${GEMINI_API_BASE}/upload/v1beta/files?key=${GEMINI_API_KEY}" \
    -H "X-Goog-Upload-Protocol: resumable" \
    -H "X-Goog-Upload-Command: start" \
    -H "X-Goog-Upload-Header-Content-Length: ${FILE_SIZE}" \
    -H "X-Goog-Upload-Header-Content-Type: audio/mp3" \
    -H "Content-Type: application/json" \
    -d '{"file": {"display_name": "voice_memo"}}' \
    -D - 2>/dev/null)

UPLOAD_URL=$(echo "$INIT_RESPONSE" | grep -i "x-goog-upload-url:" | cut -d' ' -f2 | tr -d '\r')

if [[ -z "$UPLOAD_URL" ]]; then
    log "ERROR: Failed to get upload URL"
    log "Response: $INIT_RESPONSE"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Step 2: Upload the file
log "Uploading audio to Gemini..."
UPLOAD_RESPONSE=$(curl -s -X POST "$UPLOAD_URL" \
    -H "X-Goog-Upload-Command: upload, finalize" \
    -H "X-Goog-Upload-Offset: 0" \
    -H "Content-Type: audio/mp3" \
    --data-binary @"$MP3_FILE" 2>/dev/null)

FILE_URI=$(echo "$UPLOAD_RESPONSE" | /usr/bin/jq -r '.file.uri // empty')

if [[ -z "$FILE_URI" ]]; then
    log "ERROR: Failed to upload file"
    log "Response: $UPLOAD_RESPONSE"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log "File uploaded: $FILE_URI"

# Step 3: Transcribe
log "Requesting transcription..."
TRANSCRIPTION_FILE="$TEMP_DIR/transcription.json"

# Read transcription prompt
if [[ -f "$PROMPTS_DIR/transcription-prompt.md" ]]; then
    TRANSCRIPTION_PROMPT=$(cat "$PROMPTS_DIR/transcription-prompt.md")
else
    TRANSCRIPTION_PROMPT="Transcribe this audio recording exactly as spoken. Include all words, pauses indicated by '...' and any verbal fillers. Do not summarize or paraphrase. Output only the transcription, no other text."
fi

# Build transcription request using jq for safe JSON encoding
TRANSCRIPTION_PAYLOAD=$(/usr/bin/jq -n \
    --arg prompt "$TRANSCRIPTION_PROMPT" \
    --arg file_uri "$FILE_URI" \
    '{
        contents: [{
            parts: [
                {file_data: {mime_type: "audio/mp3", file_uri: $file_uri}},
                {text: $prompt}
            ]
        }]
    }')

curl -s -X POST \
    "${GEMINI_API_BASE}/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$TRANSCRIPTION_PAYLOAD" -o "$TRANSCRIPTION_FILE" 2>/dev/null

TRANSCRIPT=$(/usr/bin/jq -r '.candidates[0].content.parts[0].text // empty' "$TRANSCRIPTION_FILE" 2>/dev/null)

if [[ -z "$TRANSCRIPT" ]]; then
    log "ERROR: Failed to get transcription"
    log "Response: $(cat "$TRANSCRIPTION_FILE")"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log "Transcription received (${#TRANSCRIPT} chars)"

# Step 4: Analyze for title, summary, tags
log "Analyzing content..."

# Read analysis prompt from Obsidian (or use default)
if [[ -f "$PROMPTS_DIR/analysis-prompt.md" ]]; then
    ANALYSIS_PROMPT_BASE=$(cat "$PROMPTS_DIR/analysis-prompt.md")
else
    ANALYSIS_PROMPT_BASE="Analyze this voice memo transcript and return a JSON object with exactly these fields:
- title: a concise descriptive title (3-7 words)
- summary: a 1-2 sentence summary of the main points
- tags: an array of 2-4 relevant topic tags (single words, lowercase, no # symbol)
- todos: an array of fully formatted Obsidian task strings. Format each as:
  \"- [ ] Task description #priority\"
  Where priority is one of: asap, today, thisweek, thismonth, thisyear

If no todos are found, return an empty array for todos.

Return ONLY valid JSON, no other text.

Transcript:"
fi
ANALYSIS_PROMPT="${ANALYSIS_PROMPT_BASE}
${TRANSCRIPT}"

# Use jq to safely construct the JSON payload
ANALYSIS_PAYLOAD=$(/usr/bin/jq -n --arg prompt "$ANALYSIS_PROMPT" '{
    contents: [{
        parts: [{
            text: $prompt
        }]
    }],
    generationConfig: {
        responseMimeType: "application/json"
    }
}')

ANALYSIS_FILE="$TEMP_DIR/analysis.json"
curl -s -X POST \
    "${GEMINI_API_BASE}/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$ANALYSIS_PAYLOAD" -o "$ANALYSIS_FILE" 2>/dev/null

ANALYSIS_JSON=$(/usr/bin/jq -r '.candidates[0].content.parts[0].text // empty' "$ANALYSIS_FILE" 2>/dev/null)

if [[ -z "$ANALYSIS_JSON" ]]; then
    log "WARNING: Failed to get analysis, using defaults"
    log "Analysis response: $(cat "$ANALYSIS_FILE")"
    TITLE="Voice Memo"
    SUMMARY="Voice memo recorded on $(date '+%Y-%m-%d')"
    TAGS='["voicememos"]'
    TODOS='[]'
else
    TITLE=$(echo "$ANALYSIS_JSON" | /usr/bin/jq -r '.title // "Voice Memo"')
    SUMMARY=$(echo "$ANALYSIS_JSON" | /usr/bin/jq -r '.summary // "Voice memo"')
    TAGS=$(echo "$ANALYSIS_JSON" | /usr/bin/jq -r '.tags // ["voicememos"]')
    TODOS=$(echo "$ANALYSIS_JSON" | /usr/bin/jq -r '.todos // []')
fi

log "Analysis complete: $TITLE"

# Get current date info
TODAY=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M')

# Format tags for YAML frontmatter (as array)
TAGS_YAML=$(echo "$TAGS" | /usr/bin/jq -r '.[] | "  - " + .')
# Always include voicememos tag
if ! echo "$TAGS_YAML" | grep -q "voicememos"; then
    TAGS_YAML="  - voicememos
$TAGS_YAML"
fi

# Format todos - AI returns pre-formatted strings, just join with newlines
TODOS_MD=""
TODO_COUNT=$(echo "$TODOS" | /usr/bin/jq 'length')
if [[ "$TODO_COUNT" -gt 0 ]]; then
    TODOS_MD="## Tasks

"
    TODOS_MD+=$(echo "$TODOS" | /usr/bin/jq -r '.[]')
    TODOS_MD+="

"
fi

# Create safe filename from title
SAFE_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 ]//g' | sed 's/  */ /g')
NOTE_FILENAME="${SAFE_TITLE}.md"
NOTE_PATH="$VOICE_MEMOS_PATH/$NOTE_FILENAME"

# Handle duplicate filenames
if [[ -f "$NOTE_PATH" ]]; then
    NOTE_FILENAME="${SAFE_TITLE} ${TODAY} ${TIME//:/-}.md"
    NOTE_PATH="$VOICE_MEMOS_PATH/$NOTE_FILENAME"
fi

# Create the note file
log "Creating note: $NOTE_PATH"
cat > "$NOTE_PATH" << MEMO
---
tags:
$TAGS_YAML
author:
  - "[[Me]]"
created: "${TODAY}"
time: "${TIME}"
status:
---

${TODOS_MD}## Summary

$SUMMARY

## Transcript

$TRANSCRIPT
MEMO

# Mark as processed
touch "$PROCESSED_MARKER"

# Cleanup
rm -rf "$TEMP_DIR"

log "SUCCESS: Voice memo saved to $NOTE_PATH"

# Optional: Delete the uploaded file from Gemini (cleanup)
FILE_NAME=$(echo "$FILE_URI" | grep -o 'files/[^"]*')
if [[ -n "$FILE_NAME" ]]; then
    curl -s -X DELETE \
        "${GEMINI_API_BASE}/v1beta/${FILE_NAME}?key=${GEMINI_API_KEY}" \
        >/dev/null 2>&1 || true
fi

exit 0

# Voice Memo to Obsidian

Automatically transcribe iOS Voice Memos and create Obsidian notes with AI-generated summaries, tags, and extracted tasks.

Lots of room to update and personalize this, but wanted to crystalize the first version i got up and running in case its useful for anyone.

This version uses cron because I generally find it more reliable than Automator, and Gemini because its cheap and reasonably reliable.

## Features

- **Automatic processing** - Polls for new voice memos every 2 minutes via cron
- **AI transcription** - Uses Google Gemini API for accurate speech-to-text
- **Smart analysis** - Extracts title, summary, tags, and tasks from content
- **Task extraction** - Pulls out action items with priority levels (#asap, #today, #thisweek, etc.)
- **Obsidian integration** - Creates properly formatted notes with YAML frontmatter
- **Customizable prompts** - Edit AI prompts directly in your Obsidian vault

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ iOS Voice   │────▶│ iCloud Sync │────▶│ Cron Job    │────▶│ Obsidian    │
│ Memos App   │     │ to Mac      │     │ (2 min)     │     │ Note        │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │ Gemini API  │
                                        │ Transcribe  │
                                        │ + Analyze   │
                                        └─────────────┘
```

1. Record a voice memo on your iPhone
2. iCloud syncs it to `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/`
3. Cron job detects new files every 2 minutes
4. Script converts audio to MP3 and uploads to Gemini
5. Gemini transcribes and analyzes the content
6. A new note is created in your Obsidian vault

## Requirements

- macOS (tested on Sonoma/Sequoia)
- [Homebrew](https://brew.sh)
- Obsidian vault
- Google Gemini API key (free tier works fine)
- iOS Voice Memos app with iCloud sync enabled

## Installation

### 1. Install dependencies

```bash
brew install ffmpeg jq
```

### 2. Get a Gemini API key

Visit [Google AI Studio](https://makersuite.google.com/app/apikey) and create an API key.

### 3. Run the installer

```bash
git clone https://github.com/yourusername/voice-memo-to-obsidian.git
cd voice-memo-to-obsidian
./install.sh
```

The installer will prompt for:
- Your Obsidian vault path
- Your Gemini API key

### 4. Grant Full Disk Access to cron

This is required for cron to read the Voice Memos directory.

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click **+** button
3. Press **Cmd+Shift+G** and type: `/usr/sbin/cron`
4. Select `cron` and enable the toggle

## Upgrading

When a new version is released:

```bash
cd voice-memo-to-obsidian
git pull
./upgrade.sh
```

The upgrade script **only updates the processing scripts**. Your config and customized prompts are preserved.

## File Types

### Upgradable Files (overwritten by `upgrade.sh`)

These are the core scripts that may receive bug fixes or new features:

| File | Location |
|------|----------|
| `voice-memo-to-obsidian.sh` | `~/.config/voice-memo/scripts/` |
| `voice-memo-watcher.sh` | `~/.config/voice-memo/scripts/` |

### User-Editable Files (never overwritten)

These files are created from samples on first install and never touched again:

| File | Location | Sample |
|------|----------|--------|
| `config` | `~/.config/voice-memo/` | `config.sample` |
| `transcription-prompt.md` | `{vault}/Areas/Voice Memo Pipeline/` | `prompts/transcription-prompt.sample.md` |
| `analysis-prompt.md` | `{vault}/Areas/Voice Memo Pipeline/` | `prompts/analysis-prompt.sample.md` |

To reset a prompt to defaults, delete it and run `./install.sh` (it will skip existing files and only create missing ones).

## Output Format

Each voice memo becomes a note in `Daily/Babble/`:

```markdown
---
tags:
  - voicememos
  - meeting
  - project
author:
  - "[[Me]]"
created: "2024-01-15"
time: "14:30"
status:
---

## Tasks

- [ ] Send follow-up email #today
- [ ] Schedule team meeting #thisweek

## Summary

Discussion about project timeline and next steps for the Q1 launch.

## Transcript

Hey, so I just got out of the meeting and wanted to capture a few thoughts...
```

## Configuration

### Config file (`~/.config/voice-memo/config`)

```bash
GEMINI_API_KEY="your-api-key"
OBSIDIAN_VAULT="/path/to/your/vault"

# Optional: change the model (default: gemini-2.5-flash)
GEMINI_MODEL="gemini-2.5-flash"
```

### Polling interval

The default is every 2 minutes. To change it, edit your crontab:

```bash
crontab -e
```

Change `*/2` to your desired interval:
- `*/1` = every minute
- `*/5` = every 5 minutes
- `*/10` = every 10 minutes

### AI Prompts

Prompts are stored in your Obsidian vault at `Areas/Voice Memo Pipeline/`:

| File | Purpose |
|------|---------|
| `transcription-prompt.md` | Instructions for transcription |
| `analysis-prompt.md` | Instructions for title, summary, tags, and task extraction |

Edit these directly in Obsidian to customize the AI behavior. Compare with the `.sample.md` files in this repo to see new features after upgrading.

## File Locations Summary

| Location | Purpose |
|----------|---------|
| `~/.config/voice-memo/config` | API key and vault path |
| `~/.config/voice-memo/scripts/` | Processing scripts |
| `~/.config/voice-memo/processed/` | Markers for processed files |
| `~/.config/voice-memo/voice-memo.log` | Activity log |
| `~/.config/voice-memo/cron.log` | Cron output |
| `{vault}/Areas/Voice Memo Pipeline/` | AI prompts |
| `{vault}/Daily/Babble/` | Output notes |

## Logs

```bash
# Watch processing activity
tail -f ~/.config/voice-memo/voice-memo.log

# Check cron output
cat ~/.config/voice-memo/cron.log
```

## Manual Usage

Process all recent memos:
```bash
~/.config/voice-memo/scripts/voice-memo-watcher.sh
```

Process a specific file:
```bash
~/.config/voice-memo/scripts/voice-memo-to-obsidian.sh "/path/to/recording.m4a"
```

## Troubleshooting

### "Operation not permitted" errors

The cron daemon needs Full Disk Access. See installation step 4.

### Watcher runs but finds 0 files

- Verify Full Disk Access is granted to `/usr/sbin/cron`
- Check that Voice Memos are syncing to your Mac (open Voice Memos app on Mac)

### Rate limit errors (429)

Gemini free tier has limits. Wait a minute and try again, or use a paid API key.

### Files not being detected

The watcher only looks for files modified in the last 10 minutes. For older files, process them manually:

```bash
~/.config/voice-memo/scripts/voice-memo-to-obsidian.sh "/path/to/file.m4a"
```

Otherwise it can very likely be a iCloud sync glitch. More often than not one side or the other will get stuck. Successive reboots of your phone/Mac usually solve this, but the best solution is time.

## Uninstall

```bash
./uninstall.sh
```

This removes the cron job and config directory. Notes and prompts in your Obsidian vault are preserved.

## Privacy

- Audio is uploaded to Google's Gemini API for processing
- Files are deleted from Gemini after processing
- No data is stored outside your local machine and Obsidian vault

## Credits

Inspired by [drew.tech's voice memo workflow](https://drew.tech/posts/ios-memos-obsidian-claude).

## License

MIT

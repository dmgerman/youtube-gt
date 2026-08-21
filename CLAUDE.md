# youtube-gt.el - Quick Reference

## Overview

An Emacs package for managing YouTube playlist information in org-mode files. Uses the YouTube Data API v3 to fetch playlist data and generates/updates org-mode tables with video information.

## CRITICAL: Git Commit Policy

**NEVER COMMIT CHANGES TO GIT**

- Claude Code is **FORBIDDEN** from creating git commits
- All commits must be made by the user explicitly
- This applies to ALL changes, no exceptions
- If you think changes should be committed, tell the user but DO NOT commit
- The user will review and commit changes when ready

## Key Features

- Fetches playlist data via YouTube Data API v3
- Channel URL support (`@username` format) to fetch all uploads
- Generates formatted org-mode tables with video metadata
- Preserves manual notes across updates
- Marks removed videos as "NA" instead of deleting
- Offset parameter to skip first N videos
- UTF-8 support for international characters

## Directory Structure

```
youtube-gt-el/
├── youtube-gt.el    # Main package source (single file)
├── README.md              # User documentation
├── CLAUDE.md              # This file (development context)
├── example.org            # Usage examples
├── test.org               # Test data file
└── TEST-RESULTS.md        # Test result documentation
```

## Core Concepts

### Directive Syntax

```org
# Playlist URL
#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PLAYLIST_ID
#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PLAYLIST_ID:offset=50

# Channel URL (fetches all uploads)
#+YOUTUBE-GT_UPDATE: https://www.youtube.com/@username/videos
#+YOUTUBE-GT_UPDATE: https://www.youtube.com/@username/videos:offset=100
```

### Generated Table Format

| Column | Content | Description |
|--------|---------|-------------|
| 1 | Index | Video position (0-based) or "NA" for removed videos |
| 2 | Note1 | User manual note (preserved on update) |
| 3 | Note2 | User manual note (preserved on update) |
| 4 | Duration | Video length (HH:MM:SS or MM:SS) |
| 5 | Published | Publication date (YYYY-MM-DD) |
| 6 | URL | Org link `[[url][video-id]]` |
| 7 | Title | Video title |

## Key Functions

### Public API

- `youtube-gt-update-all` - Update all playlist tables in buffer (interactive)

### Internal Functions

| Function | Purpose |
|----------|---------|
| `youtube-gt--get-api-key` | Get API key from authinfo or custom var |
| `youtube-gt--extract-playlist-id` | Extract playlist ID from URL |
| `youtube-gt--extract-channel-handle` | Extract @handle from channel URL |
| `youtube-gt--fetch-uploads-playlist-id` | Get uploads playlist ID for a channel |
| `youtube-gt--chunk-list` | Split list into chunks (for API batching) |
| `youtube-gt--fetch-all-videos` | Fetch all videos from playlist (handles pagination) |
| `youtube-gt--update-at-point` | Update table at current directive |
| `youtube-gt--merge-rows` | Merge old/new rows preserving notes |
| `youtube-gt--parse-table` | Parse existing org table |
| `youtube-gt--generate-table-string` | Generate org table from rows |

### Data Structures

**Video alist:**
```elisp
'((id . "VIDEO_ID")
  (title . "Video Title")
  (duration . "PT1H2M3S")   ; ISO 8601 format
  (published . "2024-01-15")
  (url . "https://www.youtube.com/watch?v=VIDEO_ID"))
```

**Table Row alist:**
```elisp
'((index . "0")
  (note1 . "")
  (note2 . "")
  (duration . "1:02:03")
  (published . "2024-01-15")
  (url . "[[https://...][VIDEO_ID]]")
  (video-id . "VIDEO_ID")
  (title . "Video Title"))
```

## Configuration

```elisp
;; API key (or use authinfo - preferred)
(setq youtube-gt-api-key "YOUR-KEY")

;; Max results per API request
(setq youtube-gt-max-results 50)

;; Authinfo host/user for key lookup
(setq youtube-gt-host-key "youtube.com")
(setq youtube-gt-user-name "dmg")

;; Org-mode directive (default: "#+YOUTUBE-GT_UPDATE")
(setq youtube-gt-directive "#+YOUTUBE-GT_UPDATE")
```

## Testing

### Interactive testing via emacsclient
```bash
# Load module
emacsclient -e '(load-file "youtube-gt.el")'

# Test update on a buffer
emacsclient -e '(with-current-buffer (find-file "test.org") (youtube-gt-update-all))'
```

## Dependencies

- Emacs 30.1+
- Built-in: `org`, `url`, `json`, `iso8601`, `auth-source`, `cl-lib`
- External: YouTube Data API v3 key

## Code Style

- Single-file package following Emacs conventions
- Lexical binding enabled
- All internal functions prefixed with `youtube-gt--`
- Uses alists for data structures (functional style)
- Avoids mutation where possible (see parent CLAUDE.md)

## Common Tasks

### Adding a new table column
1. Update `youtube-gt--video-to-row` to add new field
2. Update `youtube-gt--row-to-string` format string
3. Update `youtube-gt--parse-table-row` to parse the column
4. Update documentation in README.md

### Modifying API requests
- `youtube-gt--fetch-playlist-items` - playlist items endpoint
- `youtube-gt--fetch-video-details` - video details endpoint
- `youtube-gt--fetch-uploads-playlist-id` - channels endpoint (for @handle lookup)
- `youtube-gt--api-url` - URL construction

### Changing merge behavior
- `youtube-gt--merge-rows` handles the logic for:
  - Preserving notes from old rows
  - Marking removed videos as "NA"
  - Ordering of merged results

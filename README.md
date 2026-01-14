# youtube-playlist.el

An Emacs package for managing YouTube playlist information in org-mode files.

## Features

- Fetches playlist data from YouTube Data API v3
- Generates formatted org-mode tables with video information
- Preserves manual notes when updating tables
- Marks removed videos as "NA" instead of deleting them
- Lists videos from oldest to newest
- **Offset parameter** to skip the first N videos from a playlist
- Automatic deduplication of videos (keeps first occurrence)
- Full UTF-8 support for international characters (Japanese, emojis, etc.)
- Professional, functional, maintainable codebase

## Installation

### 1. Get a YouTube API Key

1. Go to [Google Cloud Console](https://console.developers.google.com/)
2. Create a new project or select an existing one
3. Enable the **YouTube Data API v3**
4. Create credentials (API key)
5. Copy your API key

### 2. Install the Package

Place `youtube-playlist.el` in your Emacs load path, then add to your init file:

```elisp
(require 'youtube-playlist)
```

### 3. Configure API Key

You have two options for providing the API key:

**Option A: Using authinfo (Recommended for security)**

Add to your `~/.authinfo.gpg` file:
```
machine youtube.com login dmg password YOUR-API-KEY-HERE
```

The module will automatically read the key from authinfo when needed.

**Option B: Using Emacs customization**

Set the key in your init file:
```elisp
(setq youtube-playlist-api-key "YOUR-API-KEY-HERE")
```

Or set it interactively:
```
M-x customize-variable RET youtube-playlist-api-key RET
```

## Usage

### 1. Add Playlist References

In your org-mode file, add a `#+YOUTUBE_UPDATE:` directive with a playlist URL:

```org
* My Playlist

#+YOUTUBE_UPDATE: https://www.youtube.com/playlist?list=PLPdNX2arS9MYUGoIp0qogtHZ3fXu46GQt
```

**Optional: Use offset parameter to skip videos**

You can skip the first N videos from a playlist using the `:offset=N` parameter:

```org
* Show only recent videos (skip first 100)

#+YOUTUBE_UPDATE: https://www.youtube.com/playlist?list=PLPdNX2arS9MYUGoIp0qogtHZ3fXu46GQt:offset=100
```

This will skip the first 100 videos and display only videos 100 onwards. The index column will start from the offset value (100 in this example).

### 2. Generate/Update Tables

Run the update command:
```
M-x youtube-playlist-update-all
```

This will generate a table below the directive:

```org
#+YOUTUBE_UPDATE: https://www.youtube.com/playlist?list=PLPdNX2arS9MYUGoIp0qogtHZ3fXu46GQt
| 0  |  |  |  7:13 | 2024-01-15 | [[https://www.youtube.com/watch?v=TOg98tz6ZZM][TOg98tz6ZZM]] | Video Title Here |
| 1  |  |  | 12:45 | 2024-01-20 | [[https://www.youtube.com/watch?v=abc123][abc123]]          | Another Video    |

With offset:
#+YOUTUBE_UPDATE: https://www.youtube.com/playlist?list=PLPdNX2arS9MYUGoIp0qogtHZ3fXu46GQt:offset=30
| 30 |  |  | 15:36 | 2025-07-31 | [[https://www.youtube.com/watch?v=xKEY7DnqOIk][xKEY7DnqOIk]] | 🇯🇵👩🏻‍🏫Intermediate Japanese Comprehensible Input | What's in My Mini Emergency Pouch? |
| 31 |  |  | 10:22 | 2025-08-02 | [[https://www.youtube.com/watch?v=def456][def456]]          | Another Video    |
```

### 3. Add Manual Notes

The second and third columns are reserved for your manual notes:

```org
| 0  | watched | important |  7:13 | 2024-01-15 | [[...][...]] | Video Title |
| 1  |         | to-review | 12:45 | 2024-01-20 | [[...][...]] | Another Video |
```

These notes will be **preserved** when you re-run `youtube-playlist-update-all`.

### 4. Update Behavior

When updating:
- New videos are added with sequential indices
- Existing videos retain your manual notes
- Videos removed from the playlist are marked with index "NA" but kept in the table
- Video metadata (title, date, duration) is refreshed

## Table Format

| Column | Description | Example |
|--------|-------------|---------|
| 1 | Video index (0-based) or "NA" for removed videos | `0`, `1`, `NA` |
| 2 | Manual note column 1 | `watched` |
| 3 | Manual note column 2 | `important` |
| 4 | Video duration | `7:13`, `1:23:45` |
| 5 | Publication date (ISO format) | `2024-01-15` |
| 6 | Video URL (org link with video ID as label) | `[[https://...][abc123]]` |
| 7 | Video title | `Video Title Here` |

## Configuration

### API Key

```elisp
(setq youtube-playlist-api-key "YOUR-API-KEY")
```

### Max Results Per Request

```elisp
(setq youtube-playlist-max-results 50)  ; Default: 50
```

## Requirements

- Emacs 27.1+
- Internet connection for API access
- YouTube Data API v3 key

## API Quota

The YouTube Data API has a daily quota limit. Each update operation uses:
- 1 quota unit per 50 videos (playlistItems call)
- 1 quota unit per video details batch (videos call)

The default daily quota is 10,000 units, which is sufficient for most use cases.

## Troubleshooting

### "YouTube API key not set"
Set your API key using `M-x customize-variable youtube-playlist-api-key`

### "YouTube API error: ..."
Check that:
1. Your API key is valid
2. YouTube Data API v3 is enabled in your Google Cloud project
3. You haven't exceeded your API quota
4. The playlist URL is correct and the playlist is public

### Table not updating
Ensure:
1. You're running the command in the org-mode buffer
2. The `#+YOUTUBE_UPDATE:` line has a valid playlist URL
3. Your internet connection is working

## License

This software is provided as-is without warranty.

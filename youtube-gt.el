;;; youtube-gt.el --- Update YouTube playlist tables in org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025, 2026 Daniel M. German <dmg@turingmachine.org>

;; Author: Daniel M. German <dmg@turingmachine.org>
;; Maintainer: Daniel M. German <dmg@turingmachine.org>
;; Assisted-by: Claude:claude-opus-4-7
;; Keywords: multimedia, hypermedia, tools
;; URL: https://github.com/dmgerman/youtube-gt
;; Version: 1.0.0
;; Package-Requires: ((emacs "30.1"))

;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides functionality to scan org-mode files for
;; #+YOUTUBE-GT_UPDATE: directives and generate/update tables with
;; playlist video information using the YouTube Data API v3.
;;
;; Usage:
;;   1. Set your YouTube API key: M-x customize-variable youtube-gt-api-key
;;   2. Add #+YOUTUBE-GT_UPDATE: <playlist-url> to your org file
;;   3. Run M-x youtube-gt-update-all
;;
;; The generated table includes:
;;   - Video index (0-based)
;;   - Two columns for manual notes
;;   - Video duration (HH:MM:SS)
;;   - Publication date (ISO format)
;;   - Video URL (org link)
;;   - Video title

;;; Code:

(require 'org)
(require 'url)
(require 'json)
(require 'iso8601)
(require 'auth-source)
(require 'cl-lib)

;;; Customization

(defgroup youtube-gt nil
  "YouTube playlist integration for `org-mode'."
  :group 'multimedia
  :prefix "youtube-gt-")

(defcustom youtube-gt-api-key nil
  "YouTube Data API v3 key.

Ignored if authinfo has a valid key.  Only define it if you do not
use authinfo; see `youtube-gt--get-api-key'.

Get one from https://console.developers.google.com/"
  :type '(choice (const :tag "Not set" nil)
                 (string :tag "API Key"))
  :group 'youtube-gt)

(defcustom youtube-gt-max-results 50
  "Maximum number of results to fetch per API request."
  :type 'integer
  :group 'youtube-gt)

(defcustom youtube-gt-host-key "youtube.com"
  "Host name used to find the API key in the authinfo file."
  :type 'string
  :group 'youtube-gt)

(defcustom youtube-gt-user-name "dmg"
  "User name used to find the YouTube API key in the authinfo file."
  :type 'string
  :group 'youtube-gt)

(defcustom youtube-gt-directive "#+YOUTUBE-GT_UPDATE"
  "Org-mode directive used to mark playlist/channel URLs for updating.
The directive should be followed by a colon and URL in org files."
  :type 'string
  :group 'youtube-gt)

;;; Authentication

(defun youtube-gt--get-api-key ()
  "Get YouTube API key from authinfo or custom variable.
Checks auth-source first (machine: youtube.com, login: <username>),
then falls back to `youtube-gt-api-key'."
  (or (when-let* ((auth (car (auth-source-search :host youtube-gt-host-key
                                                 :user youtube-gt-user-name
                                                   :require '(:secret)
                                                   :max 1)))
                  (secret (plist-get auth :secret)))
        (if (functionp secret)
            (funcall secret)
          secret))
      youtube-gt-api-key))

;;; Data Structures

;; Video: alist with keys
;;   'id         - YouTube video ID
;;   'title      - Video title
;;   'duration   - Duration in seconds
;;   'published  - Publication date (ISO format string)
;;   'url        - Full video URL

;; Table Row: alist with keys
;;   'index      - Video index or "NA"
;;   'note1      - First note column (manual)
;;   'note2      - Second note column (manual)
;;   'duration   - Duration string (HH:MM:SS)
;;   'published  - Publication date (ISO)
;;   'url        - Video URL
;;   'video-id   - YouTube video ID
;;   'title      - Video title

;;; Utility Functions

(defun youtube-gt--extract-playlist-id (url)
  "Extract playlist ID from URL.
Match the `list=' query parameter and stop at the first non-ID
character; YouTube playlist IDs are limited to letters, digits,
underscore, and dash.  Return nil when no ID is present."
  (when (string-match "list=\\([A-Za-z0-9_-]+\\)" url)
    (match-string 1 url)))

(defun youtube-gt--extract-channel-handle (url)
  "Extract the @handle from a channel URL.
Match `youtube.com/@' and stop at any character not permitted in a
YouTube handle (letters, digits, underscore, dash, dot).  Return
the handle with its leading `@', or nil when URL is not a channel URL."
  (when (string-match "youtube\\.com/@\\([A-Za-z0-9_.-]+\\)" url)
    (concat "@" (substring-no-properties (match-string 1 url)))))

(defun youtube-gt--extract-video-id (url)
  "Extract video ID from YouTube URL."
  (when (string-match "watch\\?v=\\([^&]+\\)" url)
    (match-string 1 url)))

(defun youtube-gt--iso8601-to-seconds (iso8601-duration)
  "Parse ISO8601-DURATION (e.g., PT1H2M3S) into total seconds.
Return nil when ISO8601-DURATION is nil or unparseable."
  (when (and iso8601-duration
             (string-match
              "PT\\(?:\\([0-9]+\\)H\\)?\\(?:\\([0-9]+\\)M\\)?\\(?:\\([0-9]+\\)S\\)?"
              iso8601-duration))
    (let ((h (if (match-string 1 iso8601-duration)
                 (string-to-number (match-string 1 iso8601-duration)) 0))
          (m (if (match-string 2 iso8601-duration)
                 (string-to-number (match-string 2 iso8601-duration)) 0))
          (s (if (match-string 3 iso8601-duration)
                 (string-to-number (match-string 3 iso8601-duration)) 0)))
      (+ (* 3600 h) (* 60 m) s))))

(defun youtube-gt--format-duration (iso8601-duration)
  "Convert ISO8601-DURATION (e.g., PT1H2M3S) to HH:MM:SS format.
Return \"N/A\" if ISO8601-DURATION is nil or invalid."
  (let ((total (youtube-gt--iso8601-to-seconds iso8601-duration)))
    (if (not total)
        "N/A"
      (let ((hours (/ total 3600))
            (minutes (/ (% total 3600) 60))
            (seconds (% total 60)))
        (if (> hours 0)
            (format "%d:%02d:%02d" hours minutes seconds)
          (format "%d:%02d" minutes seconds))))))

(defun youtube-gt--video-duration-seconds (video)
  "Return VIDEO's duration in seconds, or nil when unknown."
  (youtube-gt--iso8601-to-seconds (cdr (assoc 'duration video))))

(defun youtube-gt--format-date (iso8601-date)
  "Extract and format the date from ISO8601-DATE to YYYY-MM-DD.
Return \"N/A\" if ISO8601-DATE is nil or invalid."
  (if (and iso8601-date
           (string-match "^\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" iso8601-date))
      (match-string 1 iso8601-date)
    "N/A"))

(defun youtube-gt--make-video-url (video-id)
  "Construct YouTube video URL from VIDEO-ID."
  (format "https://www.youtube.com/watch?v=%s" video-id))

;;; YouTube API Functions

(defun youtube-gt--api-url (endpoint params)
  "Construct YouTube API URL for ENDPOINT with PARAMS."
  (let ((base-url (format "https://www.googleapis.com/youtube/v3/%s" endpoint))
        (param-string (mapconcat
                       (lambda (pair)
                         (format "%s=%s"
                                 (url-hexify-string (format "%s" (car pair)))
                                 (url-hexify-string (format "%s" (cdr pair)))))
                       params
                       "&")))
    (concat base-url "?" param-string)))

(defun youtube-gt--fetch-json (url)
  "Fetch and parse JSON from URL synchronously.
Returns parsed JSON or signals error."
  (let ((url-request-method "GET")
        (url-request-extra-headers '(("Content-Type" . "application/json"))))
    (with-current-buffer (url-retrieve-synchronously url t)
      ;; Set buffer encoding to UTF-8 to handle international characters correctly
      (set-buffer-multibyte t)
      (goto-char (point-min))
      (re-search-forward "^$")
      (decode-coding-region (point) (point-max) 'utf-8)
      (let* ((json-object-type 'alist)
             (json-array-type 'list)
             (json-key-type 'symbol)
             (response (json-read)))
        (kill-buffer)
        ;; Check for API errors
        (when (assoc 'error response)
          (let* ((error-info (cdr (assoc 'error response)))
                 (message (cdr (assoc 'message error-info))))
            (error "YouTube API error: %s" message)))
        response))))

(defun youtube-gt--fetch-playlist-items (playlist-id &optional page-token)
  "Fetch playlist items for PLAYLIST-ID.
Optional PAGE-TOKEN for pagination."
  (let ((api-key (youtube-gt--get-api-key)))
    (unless api-key
      (error "YouTube API key not set.  Use M-x customize-variable youtube-gt-api-key or add to authinfo"))
    (let* ((params `(("part" . "snippet,contentDetails")
                     ("playlistId" . ,playlist-id)
                     ("maxResults" . ,(number-to-string youtube-gt-max-results))
                     ("key" . ,api-key)))
           (params (if page-token
                       (cons `("pageToken" . ,page-token) params)
                     params))
           (url (youtube-gt--api-url "playlistItems" params)))
      (youtube-gt--fetch-json url))))

(defun youtube-gt--fetch-video-details (video-ids)
  "Fetch video details (duration) for VIDEO-IDS list."
  (let ((api-key (youtube-gt--get-api-key)))
    (unless api-key
      (error "YouTube API key not set"))
    (let* ((ids-string (mapconcat 'identity video-ids ","))
           (params `(("part" . "contentDetails")
                     ("id" . ,ids-string)
                     ("key" . ,api-key)))
           (url (youtube-gt--api-url "videos" params)))
      (youtube-gt--fetch-json url))))

(defun youtube-gt--fetch-uploads-playlist-id (handle)
  "Fetch the uploads playlist ID for a channel HANDLE.
HANDLE should be in the format @username."
  (let ((api-key (youtube-gt--get-api-key)))
    (unless api-key
      (error "YouTube API key not set"))
    (let* ((params `(("part" . "contentDetails")
                     ("forHandle" . ,handle)
                     ("key" . ,api-key)))
           (url (youtube-gt--api-url "channels" params))
           (response (youtube-gt--fetch-json url))
           (items (cdr (assoc 'items response))))
      (unless items
        (error "Channel not found: %s" handle))
      (let* ((channel (car items))
             (content-details (cdr (assoc 'contentDetails channel)))
             (related-playlists (cdr (assoc 'relatedPlaylists content-details)))
             (uploads (cdr (assoc 'uploads related-playlists))))
        (unless uploads
          (error "Could not find uploads playlist for channel: %s" handle))
        uploads))))

(defun youtube-gt--parse-video-from-item (item duration-alist)
  "Parse a video alist from playlist ITEM and DURATION-ALIST."
  (let* ((snippet (cdr (assoc 'snippet item)))
         (content-details (cdr (assoc 'contentDetails item)))
         (video-id (cdr (assoc 'videoId content-details)))
         (raw-title (cdr (assoc 'title snippet)))
         ;; Replace | with : to avoid breaking org table formatting
         (title (replace-regexp-in-string "|" ":" raw-title))
         (published (cdr (assoc 'publishedAt snippet)))
         (duration (cdr (assoc (intern video-id) duration-alist))))
    `((id . ,video-id)
      (title . ,title)
      (duration . ,duration)
      (published . ,(youtube-gt--format-date published))
      (url . ,(youtube-gt--make-video-url video-id)))))

(defun youtube-gt--chunk-list (list size)
  "Split LIST into chunks of SIZE elements."
  (let ((result '()))
    (while list
      (push (cl-subseq list 0 (min size (length list))) result)
      (setq list (nthcdr size list)))
    (nreverse result)))

(defun youtube-gt--fetch-all-videos (playlist-id)
  "Fetch all videos from PLAYLIST-ID, handling pagination.
Returns list of video alists, ordered oldest to newest."
  (let ((videos '())
        (next-page-token t))
    ;; Fetch all pages
    (while next-page-token
      (let* ((response (youtube-gt--fetch-playlist-items
                        playlist-id
                        (when (stringp next-page-token) next-page-token)))
             (items (cdr (assoc 'items response))))
        (setq videos (append videos items))
        (setq next-page-token (cdr (assoc 'nextPageToken response)))))

    ;; Deduplicate videos by video-id, keeping first occurrence
    (let* ((seen-ids (make-hash-table :test 'equal))
           (unique-videos
            (cl-remove-if (lambda (item)
                            (let ((video-id (cdr (assoc 'videoId
                                                       (cdr (assoc 'contentDetails item))))))
                              (if (gethash video-id seen-ids)
                                  t  ; Remove this item (duplicate)
                                (puthash video-id t seen-ids)
                                nil)))  ; Keep this item (first occurrence)
                          videos)))

      ;; Fetch durations in batches of 50 (API limit)
      (let* ((video-ids (mapcar (lambda (item)
                                  (cdr (assoc 'videoId
                                             (cdr (assoc 'contentDetails item)))))
                                unique-videos))
             (id-chunks (youtube-gt--chunk-list video-ids 50))
             (duration-alist
              (apply #'append
                     (mapcar (lambda (chunk)
                               (let* ((response (youtube-gt--fetch-video-details chunk))
                                      (items (cdr (assoc 'items response))))
                                 (mapcar (lambda (item)
                                           (let* ((id (cdr (assoc 'id item)))
                                                  (content (cdr (assoc 'contentDetails item)))
                                                  (duration (cdr (assoc 'duration content))))
                                             (cons (intern id) duration)))
                                         items)))
                             id-chunks))))
        ;; Parse videos and reverse to get oldest-first order
        (reverse (mapcar (lambda (item)
                           (youtube-gt--parse-video-from-item item duration-alist))
                         unique-videos))))))

;;; Table Parsing Functions

(defun youtube-gt--find-table-after-point ()
  "Find org table after point, return (start . end) positions or nil."
  (save-excursion
    (when (re-search-forward "^[[:space:]]*|" nil t)
      (beginning-of-line)
      (let ((start (point)))
        ;; Find end of table
        (while (and (not (eobp))
                    (looking-at "^[[:space:]]*|"))
          (forward-line 1))
        (cons start (point))))))

(defun youtube-gt--parse-table-row (row-string)
  "Parse an org table ROW-STRING into a table row alist.
Returns nil if row is a separator."
  (when (and row-string
             (string-match "^[[:space:]]*|" row-string)
             (not (string-match "^[[:space:]]*|-" row-string)))
    (let* ((cells (split-string row-string "|" t))
           (cells (mapcar 'string-trim cells)))
      (when (>= (length cells) 7)
        (let* ((index (nth 0 cells))
               (note1 (nth 1 cells))
               (note2 (nth 2 cells))
               (duration (nth 3 cells))
               (published (nth 4 cells))
               (url-cell (nth 5 cells))
               (title (nth 6 cells))
               (video-id (when (string-match "\\[\\[.*?v=\\([^]&]+\\)\\]\\[.*?\\]\\]" url-cell)
                          (match-string 1 url-cell))))
          `((index . ,index)
            (note1 . ,note1)
            (note2 . ,note2)
            (duration . ,duration)
            (published . ,published)
            (url . ,url-cell)
            (video-id . ,video-id)
            (title . ,title)))))))

(defun youtube-gt--parse-table (start end)
  "Parse org table between START and END positions.
Returns list of table row alists."
  (save-excursion
    (goto-char start)
    (let ((rows '()))
      (while (< (point) end)
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))
               (row (youtube-gt--parse-table-row line)))
          (when row
            (push row rows)))
        (forward-line 1))
      (nreverse rows))))

;;; Table Generation Functions

(defun youtube-gt--video-to-row (index video)
  "Convert VIDEO alist to table row alist with INDEX."
  (list (cons 'index (number-to-string index))
        (cons 'note1 (copy-sequence ""))
        (cons 'note2 (copy-sequence ""))
        (cons 'duration (youtube-gt--format-duration (cdr (assoc 'duration video))))
        (cons 'published (cdr (assoc 'published video)))
        (cons 'url (format "[[%s][%s]]"
                           (cdr (assoc 'url video))
                           (cdr (assoc 'id video))))
        (cons 'video-id (cdr (assoc 'id video)))
        (cons 'title (cdr (assoc 'title video)))))

(defun youtube-gt--row-to-string (row)
  "Convert table ROW alist to org table row string."
  (format "| %-2s | %s | %s | %5s | %s | %s | %s |"
          (cdr (assoc 'index row))
          (cdr (assoc 'note1 row))
          (cdr (assoc 'note2 row))
          (cdr (assoc 'duration row))
          (cdr (assoc 'published row))
          (cdr (assoc 'url row))
          (cdr (assoc 'title row))))

(defun youtube-gt--row-annotated-p (row)
  "Return non-nil when ROW has a non-empty note1 or note2 field.
Annotations are the user's signal that a row is worth keeping even
after it falls out of the current fetch (via `:offset', `:min-length',
or removal from the playlist)."
  (let ((n1 (cdr (assoc 'note1 row)))
        (n2 (cdr (assoc 'note2 row))))
    (or (and n1 (not (string-empty-p n1)))
        (and n2 (not (string-empty-p n2))))))

(defun youtube-gt--merge-rows (old-rows new-rows)
  "Merge OLD-ROWS with NEW-ROWS, preserving manual notes.

Every NEW-ROWS entry appears in the result with its notes merged in
from any matching OLD-ROWS entry (matched by video-id).

An OLD-ROWS entry that has no counterpart in NEW-ROWS -- because it
was filtered out by `:offset' / `:min-length' or removed from the
playlist -- is kept in the result with its index changed to \"NA\"
ONLY when it carries an annotation (see `youtube-gt--row-annotated-p').
Unannotated old rows that fall out of view are silently dropped, so
tightening a filter cleans up the table instead of accumulating
noise."
  (let* ((old-by-id (mapcar (lambda (row)
                              (cons (cdr (assoc 'video-id row)) row))
                            old-rows))
         (new-by-id (mapcar (lambda (row)
                              (cons (cdr (assoc 'video-id row)) row))
                            new-rows))
         (result '()))

    ;; Add all new rows, merging notes from old rows if they exist
    (dolist (new-pair new-by-id)
      (let* ((video-id (car new-pair))
             (new-row (cdr new-pair))
             (old-row (cdr (assoc video-id old-by-id))))
        (when old-row
          ;; Preserve manual notes
          (setcdr (assoc 'note1 new-row) (cdr (assoc 'note1 old-row)))
          (setcdr (assoc 'note2 new-row) (cdr (assoc 'note2 old-row))))
        (push new-row result)))

    ;; Add old rows that are no longer in the fetch -- but ONLY if the
    ;; user annotated them.  Unannotated rows just disappear.
    (dolist (old-pair old-by-id)
      (let* ((video-id (car old-pair))
             (old-row (cdr old-pair)))
        (when (and (not (assoc video-id new-by-id))
                   (youtube-gt--row-annotated-p old-row))
          (setcdr (assoc 'index old-row) "NA")
          (push old-row result))))

    (nreverse result)))

(defun youtube-gt--generate-table-string (rows)
  "Generate org table string from ROWS list."
  (mapconcat 'youtube-gt--row-to-string rows "\n"))

;;; Update Functions

(defconst youtube-gt--recognized-params '("offset" "min-length")
  "Directive parameter names accepted after the URL, in `:name=N' form.")

(defun youtube-gt--parse-directive-args (line)
  "Parse LINE (directive body after the colon) into (URL PARAMS).
PARAMS is an alist of (SYMBOL . INTEGER) for each recognized
`:name=N' suffix in LINE.  Return nil when LINE is malformed
--- when a `:name...' fragment does not match the strict
`:name=<digits>' shape, when an unknown `:name' is used, or when
the URL portion is not a single non-whitespace token."
  (let ((rest line)
        (params '())
        (re (concat "[[:space:]]*:\\("
                    (mapconcat #'regexp-quote
                               youtube-gt--recognized-params "\\|")
                    "\\)=\\([0-9]+\\)\\'")))
    (while (string-match re rest)
      (push (cons (intern (match-string 1 rest))
                  (string-to-number (match-string 2 rest)))
            params)
      (setq rest (substring rest 0 (match-beginning 0))))
    (setq rest (string-trim rest))
    ;; The remainder must be a single non-whitespace URL token.  Any
    ;; leftover `:name...' fragment means either a malformed value on a
    ;; recognized name (e.g. `:offset=abc') or an unknown parameter
    ;; (e.g. `:foo=1'); refuse to guess in either case.  The `://' in
    ;; the URL scheme is not matched because `/' is not a letter.
    (when (and (string-match-p "\\`\\S-+\\'" rest)
               (not (string-match-p ":[a-z][a-z-]*" rest)))
      (list rest params))))

(defun youtube-gt--update-at-point ()
  "Update YouTube playlist table at current directive line.
Return t on success; return nil when point is not on a directive.
Signal `user-error' when the directive is malformed."
  (save-excursion
    (beginning-of-line)
    (when (looking-at (concat "^[[:space:]]*"
                              (regexp-quote youtube-gt-directive)
                              ":[[:space:]]+\\(.+\\)$"))
      (let* ((line (string-trim (match-string 1)))
             (parsed (youtube-gt--parse-directive-args line))
             (_ (unless parsed
                  (user-error
                   "%s: expected \"URL\" optionally followed by \":offset=N\" and/or \":min-length=N\", got: %s"
                   youtube-gt-directive line)))
             (url (car parsed))
             (params (cadr parsed))
             (offset (or (cdr (assq 'offset params)) 0))
             (min-length (or (cdr (assq 'min-length params)) 0))
             ;; Try to extract playlist ID, or get it from channel handle
             (playlist-id (youtube-gt--extract-playlist-id url))
             (channel-handle (unless playlist-id
                               (youtube-gt--extract-channel-handle url))))
        ;; If we have a channel handle, fetch its uploads playlist ID
        (when (and channel-handle (not playlist-id))
          (message "Fetching channel info for %s..." channel-handle)
          (setq playlist-id (youtube-gt--fetch-uploads-playlist-id channel-handle)))

        (unless playlist-id
          (error "Could not extract playlist ID or channel handle from: %s" url))

        (cond
         ((and (> offset 0) (> min-length 0))
          (message "Fetching playlist %s (skipping %d, keeping >=%dm)..."
                   playlist-id offset min-length))
         ((> offset 0)
          (message "Fetching playlist %s (skipping first %d videos)..."
                   playlist-id offset))
         ((> min-length 0)
          (message "Fetching playlist %s (keeping videos >=%d minutes)..."
                   playlist-id min-length))
         (t
          (message "Fetching playlist %s..." playlist-id)))
        (let* ((all-videos (youtube-gt--fetch-all-videos playlist-id))
               (after-offset (if (> offset 0)
                                 (nthcdr offset all-videos)
                               all-videos))
               ;; Pair each surviving video with its offset-adjusted
               ;; index BEFORE filtering, so positional indices remain
               ;; meaningful when `min-length' drops middle rows.
               (indexed (seq-map-indexed
                         (lambda (v i) (cons (+ i offset) v))
                         after-offset))
               (survivors (if (> min-length 0)
                              (seq-filter
                               (lambda (pair)
                                 (let ((secs (youtube-gt--video-duration-seconds
                                              (cdr pair))))
                                   (and secs (>= secs (* 60 min-length)))))
                               indexed)
                            indexed))
               (new-rows (mapcar (lambda (pair)
                                   (youtube-gt--video-to-row (car pair)
                                                             (cdr pair)))
                                 survivors))
               (old-rows nil)
               (table-bounds nil))

          ;; Check if table exists after this line
          (forward-line 1)
          (setq table-bounds (youtube-gt--find-table-after-point))

          (when table-bounds
            ;; Parse existing table
            (setq old-rows (youtube-gt--parse-table
                           (car table-bounds)
                           (cdr table-bounds)))
            ;; Delete old table
            (delete-region (car table-bounds) (cdr table-bounds)))

          ;; Merge or use new rows
          (let* ((final-rows (if old-rows
                                 (youtube-gt--merge-rows old-rows new-rows)
                               new-rows))
                 (table-string (youtube-gt--generate-table-string final-rows)))
            ;; Insert new table
            (insert table-string "\n")
            (message "Updated playlist with %d videos" (length survivors))
            t))))))

;;;###autoload
(defun youtube-gt-update-at-point ()
  "Update the single YouTube playlist table associated with point.
The directive must be reachable without stepping across unrelated
content.  Two shapes are recognized:

  1. Point is on a `youtube-gt-directive' line -- update that table.
  2. Point is inside an org table whose line immediately above (the
     line at position (1- (org-table-begin))) is a `youtube-gt-directive'
     line -- update that table.

Any other position, or a table whose immediate predecessor line is
not a directive, signals a `user-error'."
  (interactive)
  (let ((pattern (concat "^[[:space:]]*"
                         (regexp-quote youtube-gt-directive)
                         ":")))
    (save-excursion
      (beginning-of-line)
      (cond
       ((looking-at pattern)
        (unless (youtube-gt--update-at-point)
          (user-error "Failed to update playlist at point")))
       ((org-at-table-p)
        (goto-char (org-table-begin))
        (forward-line -1)
        (beginning-of-line)
        (unless (looking-at pattern)
          (user-error "Table is not immediately preceded by a %s directive"
                      youtube-gt-directive))
        (unless (youtube-gt--update-at-point)
          (user-error "Failed to update playlist at point")))
       (t
        (user-error "Point is neither on a %s directive nor in its table"
                    youtube-gt-directive))))))

;;;###autoload
(defun youtube-gt-update-all ()
  "Update all YouTube playlist tables in the current buffer.
Scans for directives matching `youtube-gt-directive' and updates their tables."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0)
          (pattern (concat "^[[:space:]]*"
                           (regexp-quote youtube-gt-directive)
                           ":")))
      (while (re-search-forward pattern nil t)
        (beginning-of-line)
        (when (youtube-gt--update-at-point)
          (setq count (1+ count)))
        ;; Move past this directive to avoid re-processing
        (forward-line 1))
      (message "Updated %d playlist%s" count (if (= count 1) "" "s")))))

(provide 'youtube-gt)

;;; youtube-gt.el ends here

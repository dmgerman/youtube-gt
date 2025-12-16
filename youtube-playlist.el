;;; youtube-playlist.el --- Update YouTube playlist tables in org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author:
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1") (request "0.3.0"))
;; Keywords: multimedia, org-mode, youtube
;; URL:

;;; Commentary:

;; This package provides functionality to scan org-mode files for
;; #+YOUTUBE_UPDATE: directives and generate/update tables with
;; playlist video information using the YouTube Data API v3.
;;
;; Usage:
;;   1. Set your YouTube API key: M-x customize-variable youtube-playlist-api-key
;;   2. Add #+YOUTUBE_UPDATE: <playlist-url> to your org file
;;   3. Run M-x youtube-playlist-update-all
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

(defgroup youtube-playlist nil
  "YouTube playlist integration for org-mode."
  :group 'multimedia
  :prefix "youtube-playlist-")

(defcustom youtube-playlist-api-key nil
  "YouTube Data API v3 key.
Get one from https://console.developers.google.com/"
  :type '(choice (const :tag "Not set" nil)
                 (string :tag "API Key"))
  :group 'youtube-playlist)

(defcustom youtube-playlist-max-results 50
  "Maximum number of results to fetch per API request."
  :type 'integer
  :group 'youtube-playlist)

;;; Authentication

(defun youtube-playlist--get-api-key ()
  "Get YouTube API key from authinfo or custom variable.
Checks auth-source first (machine: youtube.com, login: dmg),
then falls back to `youtube-playlist-api-key'."
  (or (when-let* ((auth (car (auth-source-search :host "youtube.com"
                                                   :user "dmg"
                                                   :require '(:secret)
                                                   :max 1)))
                  (secret (plist-get auth :secret)))
        (if (functionp secret)
            (funcall secret)
          secret))
      youtube-playlist-api-key))

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

(defun youtube-playlist--extract-playlist-id (url)
  "Extract playlist ID from YouTube URL."
  (when (string-match "list=\\([^&]+\\)" url)
    (match-string 1 url)))

(defun youtube-playlist--extract-video-id (url)
  "Extract video ID from YouTube URL."
  (when (string-match "watch?v=\\([^&]+\\)" url)
    (match-string 1 url)))

(defun youtube-playlist--format-duration (iso8601-duration)
  "Convert ISO 8601 duration (e.g., PT1H2M3S) to HH:MM:SS format.
Returns \"N/A\" if duration is nil or invalid."
  (if (not iso8601-duration)
      "N/A"
    (let ((duration iso8601-duration)
          (hours 0)
          (minutes 0)
          (seconds 0))
      ;; Parse PT1H2M3S format
      (when (string-match "PT\\(?:\\([0-9]+\\)H\\)?\\(?:\\([0-9]+\\)M\\)?\\(?:\\([0-9]+\\)S\\)?" duration)
        (setq hours (if (match-string 1 duration)
                        (string-to-number (match-string 1 duration))
                      0))
        (setq minutes (if (match-string 2 duration)
                          (string-to-number (match-string 2 duration))
                        0))
        (setq seconds (if (match-string 3 duration)
                          (string-to-number (match-string 3 duration))
                        0)))
      ;; Format as HH:MM:SS or MM:SS
      (if (> hours 0)
          (format "%d:%02d:%02d" hours minutes seconds)
        (format "%d:%02d" minutes seconds)))))

(defun youtube-playlist--format-date (iso8601-date)
  "Extract and format date from ISO 8601 timestamp to YYYY-MM-DD.
Returns \"N/A\" if date is nil or invalid."
  (if (and iso8601-date
           (string-match "^\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" iso8601-date))
      (match-string 1 iso8601-date)
    "N/A"))

(defun youtube-playlist--make-video-url (video-id)
  "Construct YouTube video URL from VIDEO-ID."
  (format "https://www.youtube.com/watch?v=%s" video-id))

;;; YouTube API Functions

(defun youtube-playlist--api-url (endpoint params)
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

(defun youtube-playlist--fetch-json (url)
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

(defun youtube-playlist--fetch-playlist-items (playlist-id &optional page-token)
  "Fetch playlist items for PLAYLIST-ID.
Optional PAGE-TOKEN for pagination."
  (let ((api-key (youtube-playlist--get-api-key)))
    (unless api-key
      (error "YouTube API key not set. Use M-x customize-variable youtube-playlist-api-key or add to authinfo"))
    (let* ((params `(("part" . "snippet,contentDetails")
                     ("playlistId" . ,playlist-id)
                     ("maxResults" . ,(number-to-string youtube-playlist-max-results))
                     ("key" . ,api-key)))
           (params (if page-token
                       (cons `("pageToken" . ,page-token) params)
                     params))
           (url (youtube-playlist--api-url "playlistItems" params)))
      (youtube-playlist--fetch-json url))))

(defun youtube-playlist--fetch-video-details (video-ids)
  "Fetch video details (duration) for VIDEO-IDS list."
  (let ((api-key (youtube-playlist--get-api-key)))
    (unless api-key
      (error "YouTube API key not set"))
    (let* ((ids-string (mapconcat 'identity video-ids ","))
           (params `(("part" . "contentDetails")
                     ("id" . ,ids-string)
                     ("key" . ,api-key)))
           (url (youtube-playlist--api-url "videos" params)))
      (youtube-playlist--fetch-json url))))

(defun youtube-playlist--parse-video-from-item (item duration-alist)
  "Parse a video alist from playlist ITEM and DURATION-ALIST."
  (let* ((snippet (cdr (assoc 'snippet item)))
         (content-details (cdr (assoc 'contentDetails item)))
         (video-id (cdr (assoc 'videoId content-details)))
         (title (cdr (assoc 'title snippet)))
         (published (cdr (assoc 'publishedAt snippet)))
         (duration (cdr (assoc (intern video-id) duration-alist))))
    `((id . ,video-id)
      (title . ,title)
      (duration . ,duration)
      (published . ,(youtube-playlist--format-date published))
      (url . ,(youtube-playlist--make-video-url video-id)))))

(defun youtube-playlist--fetch-all-videos (playlist-id)
  "Fetch all videos from PLAYLIST-ID, handling pagination.
Returns list of video alists, ordered oldest to newest."
  (let ((videos '())
        (next-page-token t))
    ;; Fetch all pages
    (while next-page-token
      (let* ((response (youtube-playlist--fetch-playlist-items
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

      ;; Fetch durations in batches
      (let* ((video-ids (mapcar (lambda (item)
                                  (cdr (assoc 'videoId
                                             (cdr (assoc 'contentDetails item)))))
                                unique-videos))
             (duration-response (youtube-playlist--fetch-video-details video-ids))
             (duration-items (cdr (assoc 'items duration-response)))
             (duration-alist (mapcar (lambda (item)
                                       (let* ((id (cdr (assoc 'id item)))
                                              (content (cdr (assoc 'contentDetails item)))
                                              (duration (cdr (assoc 'duration content))))
                                         (cons (intern id) duration)))
                                     duration-items)))
        ;; Parse videos and reverse to get oldest-first order
        (reverse (mapcar (lambda (item)
                           (youtube-playlist--parse-video-from-item item duration-alist))
                         unique-videos))))))

;;; Table Parsing Functions

(defun youtube-playlist--find-table-after-point ()
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

(defun youtube-playlist--parse-table-row (row-string)
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

(defun youtube-playlist--parse-table (start end)
  "Parse org table between START and END positions.
Returns list of table row alists."
  (save-excursion
    (goto-char start)
    (let ((rows '()))
      (while (< (point) end)
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))
               (row (youtube-playlist--parse-table-row line)))
          (when row
            (push row rows)))
        (forward-line 1))
      (nreverse rows))))

;;; Table Generation Functions

(defun youtube-playlist--video-to-row (index video)
  "Convert VIDEO alist to table row alist with INDEX."
  (list (cons 'index (number-to-string index))
        (cons 'note1 (copy-sequence ""))
        (cons 'note2 (copy-sequence ""))
        (cons 'duration (youtube-playlist--format-duration (cdr (assoc 'duration video))))
        (cons 'published (cdr (assoc 'published video)))
        (cons 'url (format "[[%s][%s]]"
                           (cdr (assoc 'url video))
                           (cdr (assoc 'id video))))
        (cons 'video-id (cdr (assoc 'id video)))
        (cons 'title (cdr (assoc 'title video)))))

(defun youtube-playlist--row-to-string (row)
  "Convert table ROW alist to org table row string."
  (format "| %s | %s | %s | %s | %s | %s | %s |"
          (string-pad (cdr (assoc 'index row)) 2)
          (cdr (assoc 'note1 row))
          (cdr (assoc 'note2 row))
          (string-pad (cdr (assoc 'duration row)) 5 32 t)
          (cdr (assoc 'published row))
          (cdr (assoc 'url row))
          (cdr (assoc 'title row))))

(defun youtube-playlist--merge-rows (old-rows new-rows)
  "Merge OLD-ROWS with NEW-ROWS, preserving manual notes.
Videos no longer in playlist have index set to NA.
Returns merged list of table row alists."
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

    ;; Add old rows that are no longer in the playlist (marked as NA)
    (dolist (old-pair old-by-id)
      (let* ((video-id (car old-pair))
             (old-row (cdr old-pair)))
        (unless (assoc video-id new-by-id)
          ;; Mark as NA and add to end
          (setcdr (assoc 'index old-row) "NA")
          (push old-row result))))

    (nreverse result)))

(defun youtube-playlist--generate-table-string (rows)
  "Generate org table string from ROWS list."
  (mapconcat 'youtube-playlist--row-to-string rows "\n"))

;;; Update Functions

(defun youtube-playlist--update-at-point ()
  "Update YouTube playlist table at current #+YOUTUBE_UPDATE: line.
Returns t if successful, nil otherwise."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^[[:space:]]*#\\+YOUTUBE_UPDATE:[[:space:]]+\\(.+\\)$")
      (let* ((url (string-trim (match-string 1)))
             (playlist-id (youtube-playlist--extract-playlist-id url)))
        (unless playlist-id
          (error "Could not extract playlist ID from: %s" url))

        (message "Fetching playlist %s..." playlist-id)
        (let* ((videos (youtube-playlist--fetch-all-videos playlist-id))
               (new-rows (let ((index 0))
                           (mapcar (lambda (video)
                                     (prog1
                                         (youtube-playlist--video-to-row index video)
                                       (setq index (1+ index))))
                                   videos)))
               (old-rows nil)
               (table-bounds nil))

          ;; Check if table exists after this line
          (forward-line 1)
          (setq table-bounds (youtube-playlist--find-table-after-point))

          (when table-bounds
            ;; Parse existing table
            (setq old-rows (youtube-playlist--parse-table
                           (car table-bounds)
                           (cdr table-bounds)))
            ;; Delete old table
            (delete-region (car table-bounds) (cdr table-bounds)))

          ;; Merge or use new rows
          (let* ((final-rows (if old-rows
                                 (youtube-playlist--merge-rows old-rows new-rows)
                               new-rows))
                 (table-string (youtube-playlist--generate-table-string final-rows)))
            ;; Insert new table
            (insert table-string "\n")
            (message "Updated playlist with %d videos" (length videos))
            t))))))

;;;###autoload
(defun youtube-playlist-update-all ()
  "Update all YouTube playlist tables in the current buffer.
Scans for #+YOUTUBE_UPDATE: directives and updates their tables."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^[[:space:]]*#\\+YOUTUBE_UPDATE:" nil t)
        (beginning-of-line)
        (when (youtube-playlist--update-at-point)
          (setq count (1+ count)))
        ;; Move past this directive to avoid re-processing
        (forward-line 1))
      (message "Updated %d playlist%s" count (if (= count 1) "" "s")))))

(provide 'youtube-playlist)

;;; youtube-playlist.el ends here

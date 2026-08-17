;;; youtube-gt-test.el --- Offline unit tests for youtube-gt  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Daniel M. German

;; This file is part of youtube-gt.  See LICENSE.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Offline tests: pure helpers and merge logic exercised without any
;; network access.  Anything that reaches the YouTube API is stubbed at
;; the `youtube-gt--fetch-json' seam.  Runs under `make test'.
;;
;; Live/integration tests live in `youtube-gt-live-test.el' and are
;; opt-in via `make test-live'.

;;; Code:

(require 'ert)
(require 'cl-lib)

(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name)))))
(require 'youtube-gt)

;;; URL parsing

(ert-deftest youtube-gt-test/extract-playlist-id ()
  (should (equal (youtube-gt--extract-playlist-id
                  "https://www.youtube.com/playlist?list=PLABC123")
                 "PLABC123"))
  (should (equal (youtube-gt--extract-playlist-id
                  "https://www.youtube.com/playlist?list=PLABC123&si=xyz")
                 "PLABC123"))
  (should (null (youtube-gt--extract-playlist-id
                 "https://www.youtube.com/@someone/videos"))))

(ert-deftest youtube-gt-test/extract-channel-handle ()
  (should (equal (youtube-gt--extract-channel-handle
                  "https://www.youtube.com/@mynameisandong/videos")
                 "@mynameisandong"))
  (should (equal (youtube-gt--extract-channel-handle
                  "https://www.youtube.com/@handle")
                 "@handle"))
  (should (null (youtube-gt--extract-channel-handle
                 "https://www.youtube.com/playlist?list=PLABC"))))

(ert-deftest youtube-gt-test/extract-video-id ()
  (should (equal (youtube-gt--extract-video-id
                  "https://www.youtube.com/watch?v=abc123")
                 "abc123"))
  (should (equal (youtube-gt--extract-video-id
                  "https://www.youtube.com/watch?v=abc123&t=42s")
                 "abc123")))

;;; Duration and date formatting

(ert-deftest youtube-gt-test/format-duration-nil ()
  (should (equal (youtube-gt--format-duration nil) "N/A")))

(ert-deftest youtube-gt-test/format-duration-seconds-only ()
  (should (equal (youtube-gt--format-duration "PT45S") "0:45")))

(ert-deftest youtube-gt-test/format-duration-mm-ss ()
  (should (equal (youtube-gt--format-duration "PT7M13S") "7:13")))

(ert-deftest youtube-gt-test/format-duration-hh-mm-ss ()
  (should (equal (youtube-gt--format-duration "PT1H2M3S") "1:02:03"))
  (should (equal (youtube-gt--format-duration "PT2H") "2:00:00")))

(ert-deftest youtube-gt-test/format-date ()
  (should (equal (youtube-gt--format-date "2024-01-15T10:30:00Z") "2024-01-15"))
  (should (equal (youtube-gt--format-date nil) "N/A"))
  (should (equal (youtube-gt--format-date "garbage") "N/A")))

(ert-deftest youtube-gt-test/make-video-url ()
  (should (equal (youtube-gt--make-video-url "abc123")
                 "https://www.youtube.com/watch?v=abc123")))

;;; Chunking

(ert-deftest youtube-gt-test/chunk-list-empty ()
  (should (equal (youtube-gt--chunk-list '() 3) '())))

(ert-deftest youtube-gt-test/chunk-list-exact ()
  (should (equal (youtube-gt--chunk-list '(1 2 3 4) 2)
                 '((1 2) (3 4)))))

(ert-deftest youtube-gt-test/chunk-list-remainder ()
  (should (equal (youtube-gt--chunk-list '(1 2 3 4 5) 2)
                 '((1 2) (3 4) (5)))))

;;; API URL construction

(ert-deftest youtube-gt-test/api-url ()
  (let ((url (youtube-gt--api-url "playlistItems"
                                  '(("part" . "snippet") ("key" . "K&Y")))))
    (should (string-prefix-p "https://www.googleapis.com/youtube/v3/playlistItems?" url))
    (should (string-match-p "part=snippet" url))
    ;; Ampersand in key must be hex-encoded, not treated as a param separator.
    (should (string-match-p "key=K%26Y" url))))

;;; Table row parsing

(ert-deftest youtube-gt-test/parse-table-row-valid ()
  (let ((row (youtube-gt--parse-table-row
              "| 0 | watched | important | 7:13 | 2024-01-15 | [[https://www.youtube.com/watch?v=abc123][abc123]] | Some Title |")))
    (should (equal (cdr (assoc 'index row)) "0"))
    (should (equal (cdr (assoc 'note1 row)) "watched"))
    (should (equal (cdr (assoc 'note2 row)) "important"))
    (should (equal (cdr (assoc 'duration row)) "7:13"))
    (should (equal (cdr (assoc 'published row)) "2024-01-15"))
    (should (equal (cdr (assoc 'video-id row)) "abc123"))
    (should (equal (cdr (assoc 'title row)) "Some Title"))))

(ert-deftest youtube-gt-test/parse-table-row-separator ()
  (should (null (youtube-gt--parse-table-row "|---+---+---|"))))

(ert-deftest youtube-gt-test/parse-table-row-too-few-cells ()
  (should (null (youtube-gt--parse-table-row "| 0 | a | b |"))))

;;; Row generation

(ert-deftest youtube-gt-test/video-to-row ()
  (let* ((video '((id . "abc123")
                  (title . "Hello")
                  (duration . "PT7M13S")
                  (published . "2024-01-15")
                  (url . "https://www.youtube.com/watch?v=abc123")))
         (row (youtube-gt--video-to-row 5 video)))
    (should (equal (cdr (assoc 'index row)) "5"))
    (should (equal (cdr (assoc 'note1 row)) ""))
    (should (equal (cdr (assoc 'note2 row)) ""))
    (should (equal (cdr (assoc 'duration row)) "7:13"))
    (should (equal (cdr (assoc 'title row)) "Hello"))
    (should (equal (cdr (assoc 'video-id row)) "abc123"))))

(ert-deftest youtube-gt-test/row-to-string-roundtrip ()
  (let* ((row `((index . "3")
                (note1 . "seen")
                (note2 . "ok")
                (duration . "1:02")
                (published . "2024-01-15")
                (url . "[[https://www.youtube.com/watch?v=abc123][abc123]]")
                (video-id . "abc123")
                (title . "T")))
         (s (youtube-gt--row-to-string row))
         (parsed (youtube-gt--parse-table-row s)))
    (should (equal (cdr (assoc 'index parsed)) "3"))
    (should (equal (cdr (assoc 'note1 parsed)) "seen"))
    (should (equal (cdr (assoc 'note2 parsed)) "ok"))
    (should (equal (cdr (assoc 'video-id parsed)) "abc123"))
    (should (equal (cdr (assoc 'title parsed)) "T"))))

;;; Merge logic

(defun youtube-gt-test--mkrow (index note1 note2 vid title)
  "Build a table row alist for tests."
  `((index . ,index)
    (note1 . ,note1)
    (note2 . ,note2)
    (duration . "0:00")
    (published . "2024-01-01")
    (url . ,(format "[[https://www.youtube.com/watch?v=%s][%s]]" vid vid))
    (video-id . ,vid)
    (title . ,title)))

(ert-deftest youtube-gt-test/merge-preserves-notes ()
  (let* ((old (list (youtube-gt-test--mkrow "0" "watched" "important" "v1" "old-title-1")
                    (youtube-gt-test--mkrow "1" "" "todo" "v2" "old-title-2")))
         (new (list (youtube-gt-test--mkrow "0" "" "" "v1" "new-title-1")
                    (youtube-gt-test--mkrow "1" "" "" "v2" "new-title-2")))
         (merged (youtube-gt--merge-rows old new))
         (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) merged)))
    (should (equal (length merged) 2))
    (should (equal (cdr (assoc 'note1 (cdr (assoc "v1" by-vid)))) "watched"))
    (should (equal (cdr (assoc 'note2 (cdr (assoc "v1" by-vid)))) "important"))
    (should (equal (cdr (assoc 'note2 (cdr (assoc "v2" by-vid)))) "todo"))
    ;; Titles refresh from the new fetch even though notes stick.
    (should (equal (cdr (assoc 'title (cdr (assoc "v1" by-vid)))) "new-title-1"))))

(ert-deftest youtube-gt-test/merge-marks-annotated-removed-as-na ()
  "An old row that is annotated and no longer in the fetch stays with index NA."
  (let* ((old (list (youtube-gt-test--mkrow "0" "keep" "" "gone" "removed-title")))
         (new (list (youtube-gt-test--mkrow "0" "" "" "v1" "present-title")))
         (merged (youtube-gt--merge-rows old new))
         (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) merged)))
    (should (equal (length merged) 2))
    (should (equal (cdr (assoc 'index (cdr (assoc "gone" by-vid)))) "NA"))
    (should (equal (cdr (assoc 'note1 (cdr (assoc "gone" by-vid)))) "keep"))
    (should (equal (cdr (assoc 'index (cdr (assoc "v1" by-vid)))) "0"))))

(ert-deftest youtube-gt-test/merge-drops-unannotated-removed ()
  "An old row that is NOT annotated and no longer in the fetch is dropped."
  (let* ((old (list (youtube-gt-test--mkrow "0" "" "" "gone" "removed-title")))
         (new (list (youtube-gt-test--mkrow "0" "" "" "v1" "present-title")))
         (merged (youtube-gt--merge-rows old new))
         (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) merged)))
    (should (equal (length merged) 1))
    (should (null (assoc "gone" by-vid)))
    (should (equal (cdr (assoc 'index (cdr (assoc "v1" by-vid)))) "0"))))

(ert-deftest youtube-gt-test/merge-note2-only-still-counts-as-annotated ()
  "An annotation in note2 alone is enough to preserve the row as NA."
  (let* ((old (list (youtube-gt-test--mkrow "0" "" "starred" "gone" "removed-title")))
         (new '())
         (merged (youtube-gt--merge-rows old new))
         (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) merged)))
    (should (equal (length merged) 1))
    (should (equal (cdr (assoc 'index (cdr (assoc "gone" by-vid)))) "NA"))
    (should (equal (cdr (assoc 'note2 (cdr (assoc "gone" by-vid)))) "starred"))))

(ert-deftest youtube-gt-test/merge-partial-seed ()
  ;; Old table only has some of the new videos; new videos still appear.
  (let* ((old (list (youtube-gt-test--mkrow "2" "note-two" "" "v3" "old-3")
                    (youtube-gt-test--mkrow "3" "note-three" "" "v4" "old-4")))
         (new (list (youtube-gt-test--mkrow "0" "" "" "v1" "n1")
                    (youtube-gt-test--mkrow "1" "" "" "v2" "n2")
                    (youtube-gt-test--mkrow "2" "" "" "v3" "n3")
                    (youtube-gt-test--mkrow "3" "" "" "v4" "n4")))
         (merged (youtube-gt--merge-rows old new))
         (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) merged)))
    (should (equal (length merged) 4))
    ;; Preserved notes on the pre-seeded rows.
    (should (equal (cdr (assoc 'note1 (cdr (assoc "v3" by-vid)))) "note-two"))
    (should (equal (cdr (assoc 'note1 (cdr (assoc "v4" by-vid)))) "note-three"))
    ;; New rows come in with empty notes.
    (should (equal (cdr (assoc 'note1 (cdr (assoc "v1" by-vid)))) ""))
    (should (equal (cdr (assoc 'note1 (cdr (assoc "v2" by-vid)))) ""))))

;;; Fetch layer with mocked HTTP

(defun youtube-gt-test--stub-response (playlist-response videos-response)
  "Return a `youtube-gt--fetch-json' replacement.
PLAYLIST-RESPONSE is served for `playlistItems' URLs; VIDEOS-RESPONSE
for `videos' URLs.  Both are alists shaped like parsed JSON."
  (lambda (url)
    (cond
     ((string-match-p "/playlistItems" url) playlist-response)
     ((string-match-p "/videos" url) videos-response)
     (t (error "youtube-gt-test: unexpected URL %s" url)))))

(defun youtube-gt-test--playlist-item (video-id title published)
  "Build a playlistItems API item shaped like the real response."
  `((snippet . ((title . ,title) (publishedAt . ,published)))
    (contentDetails . ((videoId . ,video-id)))))

(ert-deftest youtube-gt-test/fetch-all-videos-mocked ()
  (let* ((playlist `((items . (,(youtube-gt-test--playlist-item "v1" "Alpha" "2024-01-01T00:00:00Z")
                               ,(youtube-gt-test--playlist-item "v2" "Beta"  "2024-01-02T00:00:00Z")))))
         (videos   `((items . (((id . "v1") (contentDetails . ((duration . "PT1M"))))
                               ((id . "v2") (contentDetails . ((duration . "PT2M"))))))))
         (result nil))
    (cl-letf (((symbol-function 'youtube-gt--get-api-key) (lambda () "FAKE"))
              ((symbol-function 'youtube-gt--fetch-json)
               (youtube-gt-test--stub-response playlist videos)))
      (setq result (youtube-gt--fetch-all-videos "PL_TEST")))
    (should (equal (length result) 2))
    ;; `--fetch-all-videos' reverses to oldest-first order.
    (should (equal (cdr (assoc 'id (car result))) "v2"))
    (should (equal (cdr (assoc 'duration (car result))) "PT2M"))))

(ert-deftest youtube-gt-test/fetch-api-error-signalled ()
  (cl-letf (((symbol-function 'youtube-gt--get-api-key) (lambda () "FAKE"))
            ((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _)
               (with-current-buffer (generate-new-buffer " *fake-http*")
                 (insert "HTTP/1.1 400 Bad Request\r\n\r\n"
                         "{\"error\": {\"message\": \"quota exceeded\"}}")
                 (current-buffer)))))
    (should-error (youtube-gt--fetch-json "https://example/videos")
                  :type 'error)))

;;; Buffer-level flow with mocked fetch

(defun youtube-gt-test--seed-buffer (directive-line rows)
  "Insert DIRECTIVE-LINE followed by ROWS (list of strings) into current buffer."
  (org-mode)
  (insert directive-line "\n")
  (dolist (r rows) (insert r "\n")))

(defun youtube-gt-test--fake-fetched (ids)
  "Build a fake fetch result: one video per id in IDS, ordered as given."
  (let ((i 0))
    (mapcar (lambda (id)
              (prog1
                  `((id . ,id) (title . ,(format "T-%s" id))
                    (duration . ,(format "PT%dM" (1+ i)))
                    (published . "2024-01-01")
                    (url . ,(format "https://www.youtube.com/watch?v=%s" id)))
                (setq i (1+ i))))
            ids)))

(ert-deftest youtube-gt-test/update-at-point-inserts-table ()
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (youtube-gt-test--seed-buffer
         "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST"
         nil)
        (youtube-gt-update-all)
        (goto-char (point-min))
        (should (search-forward "| 0 " nil t))
        (should (search-forward "v1" nil t))
        (goto-char (point-min))
        (should (search-forward "| 1 " nil t))
        (should (search-forward "v2" nil t))))))

;;; Interactive `youtube-gt-update-at-point'

(ert-deftest youtube-gt-test/update-at-point-cmd-on-directive-line ()
  "Called with point on the directive line, the command updates that table."
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (goto-char (point-min))
        (should (search-forward "v1" nil t))
        (should (search-forward "v2" nil t))))))

(ert-deftest youtube-gt-test/update-at-point-cmd-from-table-body ()
  "Point inside the table immediately below its directive: the command
walks up to `org-table-begin' and finds the directive on the previous line."
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST\n")
        (insert "| 0 |  |  | 0:00 | 2020-01-01 | [[https://www.youtube.com/watch?v=v1][v1]] | stale-1 |\n")
        (insert "| 1 |  |  | 0:00 | 2020-01-01 | [[https://www.youtube.com/watch?v=v2][v2]] | stale-2 |\n")
        ;; Put point on the second table row (well inside the table body).
        (forward-line -1)
        (youtube-gt-update-at-point)
        (goto-char (point-min))
        (should (search-forward "T-v1" nil t))
        (should (search-forward "T-v2" nil t))))))

(ert-deftest youtube-gt-test/update-at-point-cmd-errors-when-none ()
  "Point outside any directive/table combination signals a user-error."
  (with-temp-buffer
    (org-mode)
    (insert "* Just a heading\n\nSome text, no directive here.\n")
    (goto-char (point-max))
    (should-error (youtube-gt-update-at-point) :type 'user-error)))

(ert-deftest youtube-gt-test/update-at-point-cmd-errors-when-table-detached ()
  "A table whose immediate predecessor line is not a directive is rejected,
even if a matching directive exists further up in the buffer."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (with-temp-buffer
      (org-mode)
      (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST\n")
      ;; A blank line breaks the association -- the table below is no
      ;; longer immediately preceded by the directive.
      (insert "\n")
      (insert "| 0 |  |  | 0:00 | 2020-01-01 | [[https://www.youtube.com/watch?v=v1][v1]] | orphan |\n")
      (forward-line -1)
      (should-error (youtube-gt-update-at-point) :type 'user-error))))

(ert-deftest youtube-gt-test/update-at-point-cmd-errors-when-only-random-text ()
  "Point on random prose (no table, no directive) signals user-error."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (with-temp-buffer
      (org-mode)
      (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST\n")
      (insert "| 0 |  |  | 0:00 | 2020-01-01 | [[https://www.youtube.com/watch?v=v1][v1]] | x |\n")
      (insert "\n")
      (insert "Some prose well below the table.\n")
      (goto-char (point-max))
      (should-error (youtube-gt-update-at-point) :type 'user-error))))

;;; Offset directive

(ert-deftest youtube-gt-test/offset-directive-shifts-indices ()
  "`:offset=N' skips the first N fetched videos and starts the index at N."
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2" "v3" "v4" "v5"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:offset=2\n")
        (youtube-gt-update-all)
        (let* ((rows (save-excursion
                       (goto-char (point-min))
                       (let (acc)
                         (while (re-search-forward "^[[:space:]]*|" nil t)
                           (let ((line (buffer-substring-no-properties
                                        (line-beginning-position)
                                        (line-end-position))))
                             (when-let ((r (youtube-gt--parse-table-row line)))
                               (push r acc)))
                           (forward-line 1))
                         (nreverse acc)))))
          (should (equal (length rows) 3))
          (should (equal (cdr (assoc 'index (nth 0 rows))) "2"))
          (should (equal (cdr (assoc 'video-id (nth 0 rows))) "v3"))
          (should (equal (cdr (assoc 'index (nth 2 rows))) "4"))
          (should (equal (cdr (assoc 'video-id (nth 2 rows))) "v5")))))))

(ert-deftest youtube-gt-test/offset-zero-behaves-like-none ()
  "`:offset=0' is a no-op: indices start at 0, all videos included."
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:offset=0\n")
        (youtube-gt-update-all)
        (goto-char (point-min))
        (should (search-forward "| 0 " nil t))
        (should (search-forward "v1" nil t))
        (goto-char (point-min))
        (should (search-forward "| 1 " nil t))
        (should (search-forward "v2" nil t))))))

(ert-deftest youtube-gt-test/offset-with-space-before-colon ()
  "URL followed by whitespace then `:offset=N' is accepted."
  (let ((fetched (youtube-gt-test--fake-fetched '("v1" "v2" "v3"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST :offset=1\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (goto-char (point-min))
        ;; First row must be v2 at index 1 (v1 skipped).
        (should (search-forward "| 1 " nil t))
        (should (search-forward "v2" nil t))))))

;;; Malformed directive rejection

(defun youtube-gt-test--directive-should-error (line)
  "Insert LINE as a directive and assert `youtube-gt-update-at-point'
signals a `user-error'."
  (with-temp-buffer
    (org-mode)
    (insert "#+YOUTUBE-GT_UPDATE: " line "\n")
    (goto-char (point-min))
    (should-error (youtube-gt-update-at-point) :type 'user-error)))

(ert-deftest youtube-gt-test/directive-rejects-offset-with-space-instead-of-equals ()
  "`:offset 0' (space, not `=') is rejected before any API call is made."
  ;; Stub the fetch so a false-positive (silently reaching the API) shows
  ;; up as a distinct assertion failure, not a network timeout.
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST :offset 0")))

(ert-deftest youtube-gt-test/directive-rejects-trailing-garbage ()
  "A trailing extra token after the URL is rejected."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST junk")))

(ert-deftest youtube-gt-test/directive-rejects-trailing-garbage-after-offset ()
  "A trailing token after a well-formed `:offset=N' is rejected."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST:offset=0 junk")))

(ert-deftest youtube-gt-test/directive-rejects-non-numeric-offset ()
  "`:offset=abc' is rejected."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST:offset=abc")))

(ert-deftest youtube-gt-test/extract-playlist-id-stops-at-whitespace ()
  "Playlist-ID extraction never swallows trailing whitespace or offset text."
  (should (equal (youtube-gt--extract-playlist-id
                  "https://www.youtube.com/playlist?list=PLABC123 :offset 0")
                 "PLABC123"))
  (should (equal (youtube-gt--extract-playlist-id
                  "https://www.youtube.com/playlist?list=PLABC123:offset=5")
                 "PLABC123")))

;;; ISO 8601 → seconds

(ert-deftest youtube-gt-test/iso8601-to-seconds ()
  (should (equal (youtube-gt--iso8601-to-seconds "PT45S") 45))
  (should (equal (youtube-gt--iso8601-to-seconds "PT2M") 120))
  (should (equal (youtube-gt--iso8601-to-seconds "PT7M13S") (+ (* 7 60) 13)))
  (should (equal (youtube-gt--iso8601-to-seconds "PT1H2M3S")
                 (+ 3600 (* 2 60) 3)))
  (should (null (youtube-gt--iso8601-to-seconds nil))))

;;; :min-length filter

(defun youtube-gt-test--fake-videos-with-durations (specs)
  "Build fake fetched videos from SPECS, a list of (ID ISO-DURATION) pairs."
  (mapcar (lambda (spec)
            (let ((id (nth 0 spec))
                  (dur (nth 1 spec)))
              `((id . ,id) (title . ,(format "T-%s" id))
                (duration . ,dur)
                (published . "2024-01-01")
                (url . ,(format "https://www.youtube.com/watch?v=%s" id)))))
          specs))

(defun youtube-gt-test--parsed-rows ()
  "Parse every table row in the current buffer as alists."
  (save-excursion
    (goto-char (point-min))
    (let (acc)
      (while (re-search-forward "^[[:space:]]*|" nil t)
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))
          (when-let ((r (youtube-gt--parse-table-row line)))
            (push r acc)))
        (forward-line 1))
      (nreverse acc))))

(ert-deftest youtube-gt-test/min-length-filters-short-videos ()
  "`:min-length=30' drops videos under 30 minutes and keeps the rest."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT5M") ("v2" "PT45M") ("v3" "PT10M")
                    ("v4" "PT1H") ("v5" "PT20M") ("v6" "PT35M")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=30\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (ids (mapcar (lambda (r) (cdr (assoc 'video-id r))) rows)))
          (should (equal ids '("v2" "v4" "v6"))))))))

(ert-deftest youtube-gt-test/min-length-preserves-positional-indices ()
  "Surviving videos keep their original playlist positions as their index."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT5M") ("v2" "PT45M") ("v3" "PT10M")
                    ("v4" "PT1H") ("v5" "PT20M") ("v6" "PT35M")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=30\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r))
                               rows)))
          (should (equal (cdr (assoc 'index (cdr (assoc "v2" by-vid)))) "1"))
          (should (equal (cdr (assoc 'index (cdr (assoc "v4" by-vid)))) "3"))
          (should (equal (cdr (assoc 'index (cdr (assoc "v6" by-vid)))) "5")))))))

(ert-deftest youtube-gt-test/min-length-combined-with-offset ()
  "Offset applies first; indices come from the offset-adjusted position."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT5M")  ; skipped by offset
                    ("v2" "PT45M") ; skipped by offset
                    ("v3" "PT10M") ; filtered by min-length
                    ("v4" "PT1H")  ; kept at index 3
                    ("v5" "PT20M") ; filtered by min-length
                    ("v6" "PT35M"))))) ; kept at index 5
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:offset=2:min-length=30\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r))
                               rows)))
          (should (equal (length rows) 2))
          (should (equal (cdr (assoc 'index (cdr (assoc "v4" by-vid)))) "3"))
          (should (equal (cdr (assoc 'index (cdr (assoc "v6" by-vid)))) "5")))))))

(ert-deftest youtube-gt-test/min-length-param-order-does-not-matter ()
  "Params can appear in either order after the URL."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT5M") ("v2" "PT45M") ("v3" "PT1H")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=30:offset=1\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (ids (mapcar (lambda (r) (cdr (assoc 'video-id r))) rows)))
          (should (equal ids '("v2" "v3"))))))))

(ert-deftest youtube-gt-test/min-length-excludes-unknown-duration ()
  "A video whose duration is nil is excluded when a filter is active."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT45M") ("v2" nil) ("v3" "PT1H")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=30\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (ids (mapcar (lambda (r) (cdr (assoc 'video-id r))) rows)))
          (should (equal ids '("v1" "v3"))))))))

(ert-deftest youtube-gt-test/min-length-zero-includes-everything ()
  "`:min-length=0' is a no-op: all videos included, unknown duration too."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v1" "PT1M") ("v2" nil) ("v3" "PT2M")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=0\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (ids (mapcar (lambda (r) (cdr (assoc 'video-id r))) rows)))
          (should (equal ids '("v1" "v2" "v3"))))))))

(ert-deftest youtube-gt-test/min-length-filtered-videos-with-old-notes-marked-na ()
  "Videos filtered out but present in the old table are preserved as NA."
  (let ((fetched (youtube-gt-test--fake-videos-with-durations
                  '(("v-long" "PT45M") ("v-short" "PT5M")))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) fetched)))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: https://www.youtube.com/playlist?list=PL_TEST:min-length=30\n")
        (insert "| 0 | oldnote | | 0:00 | 2020-01-01 | [[https://www.youtube.com/watch?v=v-short][v-short]] | stale |\n")
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-test--parsed-rows))
               (by-vid (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r))
                               rows)))
          ;; The long one is kept.
          (should (equal (cdr (assoc 'index (cdr (assoc "v-long" by-vid)))) "0"))
          ;; The short one is preserved as NA with its annotation intact.
          (let ((s (cdr (assoc "v-short" by-vid))))
            (should s)
            (should (equal (cdr (assoc 'index s)) "NA"))
            (should (equal (cdr (assoc 'note1 s)) "oldnote"))))))))

;;; :min-length malformed directive rejection

(ert-deftest youtube-gt-test/directive-rejects-min-length-with-space ()
  "`:min-length 30' (space, not `=') is rejected, mirroring `:offset'."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST :min-length 30")))

(ert-deftest youtube-gt-test/directive-rejects-non-numeric-min-length ()
  "`:min-length=abc' is rejected."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST:min-length=abc")))

(ert-deftest youtube-gt-test/directive-rejects-unknown-param ()
  "An unrecognized `:foo=1' param is rejected, not silently ignored."
  (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
             (lambda (_id) (error "should not have been called"))))
    (youtube-gt-test--directive-should-error
     "https://www.youtube.com/playlist?list=PL_TEST:foo=1")))

(provide 'youtube-gt-test)
;;; youtube-gt-test.el ends here

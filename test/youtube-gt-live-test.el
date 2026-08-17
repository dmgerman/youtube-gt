;;; youtube-gt-live-test.el --- Live integration tests for youtube-gt  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Daniel M. German

;; This file is part of youtube-gt.  See LICENSE.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Live tests: these hit the real YouTube Data API against a fixed
;; public playlist and verify end-to-end behavior of the update flow --
;; note preservation, removal marking, partial pre-seeding, and offset
;; handling.
;;
;; Opt in: `make test-live'.  Skips (does not fail) when no API key is
;; reachable via `youtube-gt--get-api-key' or when the target playlist
;; has fewer videos than a specific test needs.  Never runs in CI --
;; MELPA-facing CI never sees a key, and quota should be spent locally.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name)))))
(require 'youtube-gt)

;; Public 11-video playlist used for these tests.
(defconst youtube-gt-live-test/playlist-id
  "PLhDPo5SPJq-U7C-KJCIULIhLlbFUzYmqZ")

(defconst youtube-gt-live-test/playlist-url
  (format "https://www.youtube.com/playlist?list=%s"
          youtube-gt-live-test/playlist-id))

;; A video ID that is NOT in the playlist.  Used to seed the "removed
;; from playlist" case; the module never re-fetches this video, it only
;; checks whether the ID appears in the fresh fetch results.
(defconst youtube-gt-live-test/foreign-video-id "My1J_97gt40")

(defun youtube-gt-live-test--require-key ()
  "Skip the current test if no YouTube API key is available."
  (unless (and (fboundp 'youtube-gt--get-api-key)
               (stringp (ignore-errors (youtube-gt--get-api-key))))
    (ert-skip "No YouTube API key resolvable via youtube-gt--get-api-key")))

(defun youtube-gt-live-test--fetch-ids ()
  "Return the ordered list of video IDs currently in the test playlist.
Skips the test on network/API failure."
  (condition-case err
      (mapcar (lambda (v) (cdr (assoc 'id v)))
              (youtube-gt--fetch-all-videos youtube-gt-live-test/playlist-id))
    (error (ert-skip (format "Live fetch failed: %s" (error-message-string err))))))

(defun youtube-gt-live-test--seed-row (index note1 note2 video-id title)
  "Build a table row string for a seeded old row."
  (format "| %-2s | %s | %s | %5s | %s | [[https://www.youtube.com/watch?v=%s][%s]] | %s |"
          index note1 note2 "0:00" "2000-01-01" video-id video-id title))

(defun youtube-gt-live-test--parse-buffer-rows ()
  "Parse every table row in the current buffer and return them as alists."
  (save-excursion
    (goto-char (point-min))
    (let ((rows '()))
      (while (re-search-forward "^[[:space:]]*|" nil t)
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))
               (row (youtube-gt--parse-table-row line)))
          (when row (push row rows)))
        (forward-line 1))
      (nreverse rows))))

(defun youtube-gt-live-test--row-by-vid (rows)
  "Index parsed ROWS by video-id."
  (mapcar (lambda (r) (cons (cdr (assoc 'video-id r)) r)) rows))

;;; Tests

(ert-deftest youtube-gt-live-test/fetch-shape ()
  "The live playlist fetch returns well-formed video alists."
  (youtube-gt-live-test--require-key)
  (let ((videos (youtube-gt--fetch-all-videos youtube-gt-live-test/playlist-id)))
    (should (>= (length videos) 1))
    (dolist (v videos)
      (should (stringp (cdr (assoc 'id v))))
      (should (> (length (cdr (assoc 'id v))) 0))
      (should (stringp (cdr (assoc 'title v))))
      (should (stringp (cdr (assoc 'published v))))
      (should (string-match-p "^https://www\\.youtube\\.com/watch\\?v="
                              (cdr (assoc 'url v)))))))

(ert-deftest youtube-gt-live-test/mutation-preserves-annotations ()
  "Pre-seed 2 rows with notes; after live update, notes must persist on those IDs."
  (youtube-gt-live-test--require-key)
  (let* ((ids (youtube-gt-live-test--fetch-ids))
         (_ (when (< (length ids) 3)
              (ert-skip "playlist too small for mutation test")))
         (vid-a (nth 0 ids))
         (vid-b (nth 2 ids)))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (let ((fetched (youtube-gt--fetch-all-videos
                               youtube-gt-live-test/playlist-id)))
                 (lambda (_id) fetched))))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: " youtube-gt-live-test/playlist-url "\n")
        (insert (youtube-gt-live-test--seed-row "0" "watched" "important"
                                                vid-a "seed-title-a") "\n")
        (insert (youtube-gt-live-test--seed-row "2" "todo" "review"
                                                vid-b "seed-title-b") "\n")
        (youtube-gt-update-all)
        (let* ((rows (youtube-gt-live-test--parse-buffer-rows))
               (by-vid (youtube-gt-live-test--row-by-vid rows)))
          (should (equal (length rows) (length ids)))
          (let ((a (cdr (assoc vid-a by-vid))))
            (should a)
            (should (equal (cdr (assoc 'note1 a)) "watched"))
            (should (equal (cdr (assoc 'note2 a)) "important")))
          (let ((b (cdr (assoc vid-b by-vid))))
            (should b)
            (should (equal (cdr (assoc 'note1 b)) "todo"))
            (should (equal (cdr (assoc 'note2 b)) "review"))))))))

(ert-deftest youtube-gt-live-test/removed-video-marked-na ()
  "A seeded video absent from the playlist is preserved with index NA and its note intact."
  (youtube-gt-live-test--require-key)
  (let* ((ids (youtube-gt-live-test--fetch-ids))
         (_ (when (< (length ids) 1)
              (ert-skip "playlist empty")))
         (kept-vid (nth 0 ids))
         (gone-vid youtube-gt-live-test/foreign-video-id))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (let ((fetched (youtube-gt--fetch-all-videos
                               youtube-gt-live-test/playlist-id)))
                 (lambda (_id) fetched))))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: " youtube-gt-live-test/playlist-url "\n")
        (insert (youtube-gt-live-test--seed-row "0" "still-here" ""
                                                kept-vid "seed-kept") "\n")
        (insert (youtube-gt-live-test--seed-row "99" "keepthis" "was-here"
                                                gone-vid "seed-gone") "\n")
        (youtube-gt-update-all)
        (let* ((rows (youtube-gt-live-test--parse-buffer-rows))
               (by-vid (youtube-gt-live-test--row-by-vid rows)))
          ;; Row for the foreign video is still in the buffer, marked NA,
          ;; with its annotation intact.
          (let ((gone (cdr (assoc gone-vid by-vid))))
            (should gone)
            (should (equal (cdr (assoc 'index gone)) "NA"))
            (should (equal (cdr (assoc 'note1 gone)) "keepthis"))
            (should (equal (cdr (assoc 'note2 gone)) "was-here")))
          ;; The still-present video keeps its note and gets a real index.
          (let ((kept (cdr (assoc kept-vid by-vid))))
            (should kept)
            (should (not (equal (cdr (assoc 'index kept)) "NA")))
            (should (equal (cdr (assoc 'note1 kept)) "still-here"))))))))

(ert-deftest youtube-gt-live-test/partial-seed-fills-missing ()
  "User pre-seeded only the tail of the playlist; update must fill in the head
without losing the tail annotations."
  (youtube-gt-live-test--require-key)
  (let* ((ids (youtube-gt-live-test--fetch-ids))
         (n (length ids))
         (_ (when (< n 4)
              (ert-skip "playlist too small for partial-seed test")))
         ;; Seed the last two videos ("videos 3 and 4" in the user's phrasing,
         ;; adapted to whatever the playlist length is).
         (tail-a (nth (- n 2) ids))
         (tail-b (nth (- n 1) ids)))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (let ((fetched (youtube-gt--fetch-all-videos
                               youtube-gt-live-test/playlist-id)))
                 (lambda (_id) fetched))))
      (with-temp-buffer
        (org-mode)
        (insert "#+YOUTUBE-GT_UPDATE: " youtube-gt-live-test/playlist-url "\n")
        (insert (youtube-gt-live-test--seed-row
                 (number-to-string (- n 2)) "tail-note-a" ""
                 tail-a "seed-tail-a") "\n")
        (insert (youtube-gt-live-test--seed-row
                 (number-to-string (- n 1)) "tail-note-b" "second"
                 tail-b "seed-tail-b") "\n")
        (youtube-gt-update-all)
        (let* ((rows (youtube-gt-live-test--parse-buffer-rows))
               (by-vid (youtube-gt-live-test--row-by-vid rows)))
          ;; All playlist videos are now in the buffer.
          (should (equal (length rows) n))
          (dolist (id ids)
            (should (cdr (assoc id by-vid))))
          ;; Tail annotations survived.
          (let ((a (cdr (assoc tail-a by-vid)))
                (b (cdr (assoc tail-b by-vid))))
            (should (equal (cdr (assoc 'note1 a)) "tail-note-a"))
            (should (equal (cdr (assoc 'note1 b)) "tail-note-b"))
            (should (equal (cdr (assoc 'note2 b)) "second")))
          ;; Newly filled-in rows (the head that wasn't pre-seeded) carry
          ;; empty notes.
          (let ((head (cdr (assoc (nth 0 ids) by-vid))))
            (should head)
            (should (equal (cdr (assoc 'note1 head)) ""))
            (should (equal (cdr (assoc 'note2 head)) ""))))))))

(ert-deftest youtube-gt-live-test/min-length-directive ()
  "`:min-length=N' keeps only videos whose duration is at least N minutes,
preserves the videos' original playlist positions as indices, and drops
any video whose duration is unknown."
  (youtube-gt-live-test--require-key)
  (let* ((videos (condition-case err
                     (youtube-gt--fetch-all-videos
                      youtube-gt-live-test/playlist-id)
                   (error (ert-skip
                           (format "Live fetch failed: %s"
                                   (error-message-string err))))))
         (durations (mapcar #'youtube-gt--video-duration-seconds videos))
         (_ (when (or (< (length videos) 3)
                      (seq-some #'null durations))
              (ert-skip "playlist too small or has unknown durations")))
         ;; Pick a threshold that will split the playlist: half a minute
         ;; below the median duration, rounded to the nearest minute.
         (sorted (sort (copy-sequence durations) #'<))
         (median-secs (nth (/ (length sorted) 2) sorted))
         (threshold-min (max 1 (/ median-secs 60)))
         (expected-survivors
          (cl-loop for v in videos
                   for i from 0
                   for secs = (youtube-gt--video-duration-seconds v)
                   when (and secs (>= secs (* 60 threshold-min)))
                   collect (cons i (cdr (assoc 'id v))))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (lambda (_id) videos)))
      (with-temp-buffer
        (org-mode)
        (insert (format "#+YOUTUBE-GT_UPDATE: %s:min-length=%d\n"
                        youtube-gt-live-test/playlist-url threshold-min))
        (goto-char (point-min))
        (youtube-gt-update-at-point)
        (let* ((rows (youtube-gt-live-test--parse-buffer-rows))
               (got (mapcar (lambda (r)
                              (cons (string-to-number (cdr (assoc 'index r)))
                                    (cdr (assoc 'video-id r))))
                            rows)))
          (should (equal (length rows) (length expected-survivors)))
          (should (equal got expected-survivors)))))))

(ert-deftest youtube-gt-live-test/offset-directive ()
  "`:offset=N' skips the first N videos and starts the index at N."
  (youtube-gt-live-test--require-key)
  (let* ((ids (youtube-gt-live-test--fetch-ids))
         (n (length ids))
         (offset 2)
         (_ (when (<= n offset)
              (ert-skip "playlist too small for offset test"))))
    (cl-letf (((symbol-function 'youtube-gt--fetch-all-videos)
               (let ((fetched (youtube-gt--fetch-all-videos
                               youtube-gt-live-test/playlist-id)))
                 (lambda (_id) fetched))))
      (with-temp-buffer
        (org-mode)
        (insert (format "#+YOUTUBE-GT_UPDATE: %s:offset=%d\n"
                        youtube-gt-live-test/playlist-url offset))
        (youtube-gt-update-all)
        (let* ((rows (youtube-gt-live-test--parse-buffer-rows))
               (first-index (cdr (assoc 'index (car rows)))))
          (should (equal (length rows) (- n offset)))
          (should (equal first-index (number-to-string offset))))))))

(provide 'youtube-gt-live-test)
;;; youtube-gt-live-test.el ends here

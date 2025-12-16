;;; test-manual-update.el --- Test manual notes preservation -*- lexical-binding: t; -*-

;;; Code:

;; Load the module
(add-to-list 'load-path default-directory)
(require 'youtube-playlist)

(message "=== Testing Manual Notes Preservation for -mWoYWktTDE ===\n")

(let ((test-file (expand-file-name "test.org" default-directory)))
  (with-current-buffer (find-file-noselect test-file)
    ;; Check current state before update
    (message "Before update:")
    (goto-char (point-min))
    (when (re-search-forward "\\[-mWoYWktTDE\\].*Japanese Restaurant Chain Tier List" nil t)
      (beginning-of-line)
      (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
        (message "  %s" line)))

    ;; Run update
    (message "\nRunning youtube-playlist-update-all...")
    (youtube-playlist-update-all)

    ;; Check after update
    (message "\nAfter update:")
    (goto-char (point-min))
    (let ((found nil))
      (while (re-search-forward "\\[-mWoYWktTDE\\].*Japanese Restaurant Chain Tier List" nil t)
        (beginning-of-line)
        (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
          (message "  %s" line)
          ;; Check if manual notes are preserved
          (when (string-match "\\[2025-11-08 Sat\\]" line)
            (when (string-match "half only" line)
              (setq found t))))))

      (if found
          (message "\n✓✓✓ SUCCESS: Manual notes '[2025-11-08 Sat]' and 'half only' were preserved!")
        (message "\n✗✗✗ FAILURE: Manual notes were lost")))

    ;; Save the file
    (write-file test-file)
    (message "\nSaved updated file")))

(message "\n=== Test Complete ===")

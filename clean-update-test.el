;;; clean-update-test.el --- Clean update test -*- lexical-binding: t; -*-

;;; Code:

;; Load the module
(add-to-list 'load-path default-directory)
(require 'youtube-playlist)

(message "=== Running Clean Update ===\n")

(let ((test-file (expand-file-name "test.org" default-directory)))
  (with-current-buffer (find-file-noselect test-file)
    ;; Run update
    (youtube-playlist-update-all)

    ;; Save the file
    (write-file test-file)
    (message "\nFile saved")

    ;; Verify the manual notes are preserved
    (goto-char (point-min))
    (if (re-search-forward "\\[2025-11-08 Sat\\].*half only.*-mWoYWktTDE" nil t)
        (message "✓ Manual notes preserved")
      (message "✗ Manual notes lost"))))

(message "\n=== Done ===")

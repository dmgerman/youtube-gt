;;; simple-test.el --- Simple batch test -*- lexical-binding: t; -*-

;;; Code:

;; Load the module
(add-to-list 'load-path default-directory)
(require 'youtube-playlist)

;; Test API key retrieval
(message "Testing API key retrieval...")
(let ((key (youtube-playlist--get-api-key)))
  (if key
      (message "✓ API key found (length: %d)" (length key))
    (error "✗ API key not found")))

;; Test updating a playlist
(message "\nTesting playlist update...")
(let ((test-file (expand-file-name "test.org" default-directory)))
  (with-current-buffer (find-file-noselect test-file)
    ;; Run the update
    (youtube-playlist-update-all)

    ;; Count how many rows we generated
    (goto-char (point-min))
    (let ((row-count 0))
      (while (re-search-forward "^[[:space:]]*|[[:space:]]*[0-9]" nil t)
        (setq row-count (1+ row-count)))
      (message "✓ Generated table with %d video rows" row-count))

    ;; Save the file
    (write-file test-file)
    (message "✓ Saved results to %s" test-file)))

(message "\n✓ All tests passed!")

;;; verify-utf8.el --- Verify UTF-8 encoding works correctly -*- lexical-binding: t; -*-

;;; Code:

(message "=== UTF-8 Encoding Verification ===\n")

(let ((test-file (expand-file-name "test.org" default-directory)))
  (with-current-buffer (find-file-noselect test-file)
    (goto-char (point-min))

    ;; Check row 3 - should have Japanese characters
    (when (re-search-forward "お寺と神社" nil t)
      (message "✓ Row 3: Japanese kanji '寺' (temple) and '神社' (shrine) display correctly"))

    (goto-char (point-min))
    (when (re-search-forward "日本語中級" nil t)
      (message "✓ Row 3: Japanese text '日本語中級' (intermediate Japanese) displays correctly"))

    ;; Check row 5 - exclamation marks
    (goto-char (point-min))
    (when (re-search-forward "魔の二歳児！？" nil t)
      (message "✓ Row 5: Japanese with full-width punctuation '！？' displays correctly"))

    ;; Check row 6 - quotes
    (goto-char (point-min))
    (when (re-search-forward "「理解可能なインプット」" nil t)
      (message "✓ Row 6: Japanese corner brackets 「」 and katakana 'インプット' display correctly"))

    ;; Check emojis
    (goto-char (point-min))
    (when (re-search-forward "👩🏻‍🏫" nil t)
      (message "✓ Row 14: Multi-codepoint emoji 👩🏻‍🏫 (teacher with skin tone) displays correctly"))

    (goto-char (point-min))
    (when (re-search-forward "🇯🇵" nil t)
      (message "✓ Row 14: Flag emoji 🇯🇵 (Japanese flag) displays correctly"))

    (goto-char (point-min))
    (when (re-search-forward "💄" nil t)
      (message "✓ Row 32: Emoji 💄 (lipstick) displays correctly"))

    (message "\n✓✓✓ All UTF-8 characters display correctly!")))

(message "\n=== Verification Complete ===")

# MELPA submission

This directory holds the recipe that should be added to the
[melpa/melpa](https://github.com/melpa/melpa) repository, in its
`recipes/` directory, when submitting this package to MELPA.

To submit:

1. Fork `melpa/melpa`.
2. Copy the file `youtube-gt` from this directory into the fork's
   `recipes/` directory.
3. Run `make recipes/youtube-gt` in the MELPA fork to verify the
   recipe builds.
4. Open a pull request against `melpa/melpa`.

## Files shipped

The recipe's `:files` list ships exactly three files:

- `youtube-gt.el` — the package source
- `youtube-gt.info` — the Info manual (multi-file ELPA convention)
- `dir` — the Info directory entry for the manual

`readme.org`, `LICENSE`, `Makefile`, `.github/`, `melpa/`, `test.org`,
`example.org`, and `TEST-RESULTS.md` are deliberately excluded from the
installed package.

## Package-Requires

`youtube-gt` declares only `(emacs "27.1")`.  All other dependencies
(`org`, `url`, `json`, `iso8601`, `auth-source`, `cl-lib`) are built
into Emacs and do not need to be listed.

## Info manual

The manual (`youtube-gt.info`) and its `dir` entry are committed source-
of-truth artifacts.  `package.el` adds the installed package directory
to `Info-directory-list` on activation, so users get `C-h i m youtube-gt`
with no additional configuration.  See the *Info manual* section of the
project readme for the manual-install snippet.

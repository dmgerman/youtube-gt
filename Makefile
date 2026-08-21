# Makefile for youtube-gt.
#
# Package-specific settings only; every shared rule lives in
# Makefile.common, which is an identical copy across the dmg packages.
# Run `make help' for the target list, and see the header of
# Makefile.common for what each variable below controls.

PACKAGE = youtube-gt

# One-file package; listed so a future split stays mechanical.
EL_FILES = youtube-gt.el

# No runtime dependencies — youtube-gt uses only built-in libraries
# (url, json, iso8601, auth-source, cl-lib).  `package-lint' is the
# lint tool itself.
DEPS = package-lint

# Offline suite only.  test/youtube-gt-live-test.el is deliberately
# excluded from `test' and reachable through `make test-live'.
TEST_FILES = test/youtube-gt-test.el

INFO_SRC = readme.org

HELP_EXTRA = "  make test-live      run the live YouTube API suite (opt-in)" \
             "  make test-all       test + test-live"

include Makefile.common

# Live integration tests against the real YouTube API.  Reads the key
# from authinfo via `youtube-gt--get-api-key'.  Individual tests skip
# themselves when the key is unavailable, so `make test-live' with no
# key is a no-op rather than a failure.  NOT wired into `check' or CI
# (MELPA-facing runs never carry a key, and quota is finite).
.PHONY: test-live test-all

test-live:
	$(EMACS) -Q --batch -L . \
	  -l test/youtube-gt-live-test.el \
	  -f ert-run-tests-batch-and-exit

test-all: test test-live

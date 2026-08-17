# Top-level Makefile for youtube-gt.
#
# Targets:
#   make               — compile + info (default)
#   make lint          — package-lint every youtube-gt*.el file
#   make checkdoc      — checkdoc every youtube-gt*.el (errors on any warning)
#   make check-declare — verify declare-function file arguments
#   make compile       — byte-compile every youtube-gt*.el (errors on warning)
#   make test          — run offline ERT tests (test/youtube-gt-test.el)
#   make test-live     — run live integration tests against YouTube
#                        (test/youtube-gt-live-test.el).  Opt-in: hits
#                        the real API using the key from authinfo.  Not
#                        wired into `check' or CI.
#   make test-all      — test + test-live
#   make info          — rebuild youtube-gt.info and dir from readme.org
#                        (both are committed artifacts, not cleaned).
#   make clean         — remove every *.elc
#   make check         — compile + lint + checkdoc + check-declare + info
#   make check-30      — `make check' pinned to $(EMACS_30)
#   make check-31      — `make check' pinned to $(EMACS_31)
#   make check-all     — check-30 + check-31 (pre-push guard)
#   make check-ci      — alias for check-30 (matches CI matrix)
#   make help          — show this table
#
# Override the Emacs binary by passing EMACS=path/to/emacs.

EMACS      ?= emacs
EMACS_30   ?= /opt/homebrew/opt/emacs-plus@30/bin/emacs
EMACS_31   ?= /opt/homebrew/opt/emacs-plus@31/bin/emacs
CI_EMACS   ?= $(EMACS_30)

# One-file package; list here to make future splits mechanical.
EL_FILES = youtube-gt.el

# Project-local ELPA so the user's package dir is not touched and CI
# starts from a clean slate each run.
ELPA_DIR = .elpa

# Dependencies installed into the project-local ELPA before lint.
# `package-lint' is the lint tool itself.  No runtime deps — youtube-gt
# uses only built-in libraries (url, json, iso8601, auth-source, cl-lib).
DEPS = package-lint

# Common Emacs invocation header: project-local package-user-dir, MELPA in
# package-archives, package-initialize so installed packages are on load-path.
EMACS_BATCH = $(EMACS) -Q --batch \
  --eval "(setq package-user-dir (expand-file-name \"$(ELPA_DIR)\"))" \
  --eval "(require 'package)" \
  --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" \
  --eval "(package-initialize)"

define assert-emacs
	@if [ ! -x "$($(1))" ]; then \
	  echo "$(1) not executable: $($(1))"; \
	  echo "Install with: brew install emacs-plus@$$(echo $(1) | sed -E 's/[^0-9]//g')"; \
	  echo "Or override: make <target> $(1)=/path/to/emacs"; \
	  exit 1; \
	fi
endef

.PHONY: default lint checkdoc check-declare compile test test-live \
        test-all clean check check-ci check-30 check-31 check-all \
        checkdoc-30 checkdoc-31 checkdoc-all info help

default: compile info

help:
	@sed -n 's/^#   //p; /^# Override/q' Makefile

$(ELPA_DIR):
	@mkdir -p $@

$(ELPA_DIR)/.installed: | $(ELPA_DIR)
	$(EMACS_BATCH) \
	  --eval "(unless package-archive-contents (package-refresh-contents))" \
	  $(foreach pkg,$(DEPS),--eval "(unless (package-installed-p '$(pkg)) (package-install '$(pkg)))")
	@touch $@

lint: $(ELPA_DIR)/.installed
	$(EMACS_BATCH) \
	  --eval "(require 'package-lint)" \
	  -f package-lint-batch-and-exit $(EL_FILES)

# checkdoc runs in batch via `checkdoc-file'; warnings go to *Warnings*
# via `display-warning' and do NOT cause a non-zero exit on their own.
# Peek at the buffer after each file and exit 1 on the first warning.
checkdoc:
	@$(EMACS_BATCH) \
	  -L . \
	  --eval "(require 'checkdoc)" \
	  --eval "(let ((had-issue nil)) \
	            (dolist (f command-line-args-left) \
	              (with-current-buffer (get-buffer-create \"*Warnings*\") (erase-buffer)) \
	              (checkdoc-file f) \
	              (when (> (buffer-size (get-buffer-create \"*Warnings*\")) 0) \
	                (setq had-issue t))) \
	            (when had-issue (kill-emacs 1)))" \
	  $(EL_FILES)

# check-declare loads each declare-function target and verifies the
# function is defined there.  Exits 1 on any finding.
check-declare:
	@$(EMACS_BATCH) \
	  -L . \
	  --eval "(require 'check-declare)" \
	  --eval "(let ((had-issue nil)) \
	            (dolist (f command-line-args-left) \
	              (when (check-declare-file f) \
	                (setq had-issue t))) \
	            (when had-issue \
	              (with-current-buffer (get-buffer-create check-declare-warning-buffer) \
	                (princ (buffer-string))) \
	              (kill-emacs 1)))" \
	  $(EL_FILES)

# Compile each file in a fresh subprocess so a leaked definition from one
# cannot mask a missing `require' in another.  All warnings are fatal.
compile: $(ELPA_DIR)/.installed
	@set -e; \
	for f in $(EL_FILES); do \
	  echo "==> compiling $$f"; \
	  $(EMACS_BATCH) \
	    --eval "(setq byte-compile-error-on-warn t)" \
	    -L . \
	    -f batch-byte-compile $$f; \
	done

# Offline ERT suite.  No network, no API key required.  Wired into
# `check' and the CI workflow.
test:
	$(EMACS) -Q --batch -L . \
	  -l test/youtube-gt-test.el \
	  -f ert-run-tests-batch-and-exit

# Live integration tests against the real YouTube API.  Reads the key
# from authinfo via `youtube-gt--get-api-key'.  Individual tests skip
# themselves when the key is unavailable, so `make test-live' with no
# key is a no-op rather than a failure.  NOT wired into `check' or CI
# (MELPA-facing runs never carry a key, and quota is finite).
test-live:
	$(EMACS) -Q --batch -L . \
	  -l test/youtube-gt-live-test.el \
	  -f ert-run-tests-batch-and-exit

test-all: test test-live

clean:
	rm -f *.elc

# Info manual (multi-file ELPA convention): youtube-gt.info and dir both
# live at the package root and are committed.  `make clean' does NOT
# touch them -- they are source-of-truth artifacts consumed by ELPA
# activation.  Regenerate after editing readme.org.
INFO_FILE = youtube-gt.info
INFO_DIR  = dir

info: $(INFO_FILE) $(INFO_DIR)

# Stage readme.org as youtube-gt.org so Org's basename-derived output
# filename matches `#+texinfo_filename'.  Without this, Org produces
# readme.texi -> youtube-gt.info (from @setfilename) and then its
# post-processing looks for readme.info and fails.
$(INFO_FILE): readme.org
	cp readme.org youtube-gt.org
	$(EMACS) -Q --batch \
	  --eval "(setq load-prefer-newer t)" \
	  --eval "(require 'ox-texinfo)" \
	  youtube-gt.org \
	  -f org-texinfo-export-to-info
	rm -f youtube-gt.org youtube-gt.texi

$(INFO_DIR): $(INFO_FILE)
	install-info --info-file=$(INFO_FILE) --dir-file=$(INFO_DIR)

check: compile lint checkdoc check-declare test info

# Per-version target family.  `make check-all' is the pre-push guard.
check-30:      ; $(call assert-emacs,EMACS_30) ; $(MAKE) EMACS=$(EMACS_30) check
check-31:      ; $(call assert-emacs,EMACS_31) ; $(MAKE) EMACS=$(EMACS_31) check
check-all:     check-30 check-31
check-ci:      check-30

checkdoc-30:   ; $(call assert-emacs,EMACS_30) ; $(MAKE) EMACS=$(EMACS_30) checkdoc
checkdoc-31:   ; $(call assert-emacs,EMACS_31) ; $(MAKE) EMACS=$(EMACS_31) checkdoc
checkdoc-all:  checkdoc-30 checkdoc-31

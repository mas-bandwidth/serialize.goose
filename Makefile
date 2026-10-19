# Makefile -- serialize.goose (DESIGN.md, (g) THE RUNNER).
#
# Goose v2026.2, pinned (aardappel/goose tag v2026.2, commit 7ad96d6d47f9).
# To populate dist/ (gitignored), run `make dist-goose` once:
#   url:    https://github.com/aardappel/goose/releases/download/v2026.2/goose-v2026.2-linux-x64.tar.gz
#   sha256: f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c
#   untarred into dist/goose-v2026.2-linux-x64/ (goose, stdlib/, tcclib/)
#
# make test          run every test/*/*_test.goose
# make test T=<name> run the files of test/<name>/ only
#
# A later card adds its own targets in its own make/<card>.mk, included below,
# so no two cards edit this file.

GOOSE_VERSION := v2026.2
GOOSE_TAR     := goose-$(GOOSE_VERSION)-linux-x64.tar.gz
GOOSE_URL     := https://github.com/aardappel/goose/releases/download/$(GOOSE_VERSION)/$(GOOSE_TAR)
GOOSE_SHA     := f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c
GOOSE_DIST    := $(CURDIR)/dist/goose-$(GOOSE_VERSION)-linux-x64
GOOSE        ?= $(GOOSE_DIST)/goose
export GOOSE

.PHONY: all dist-goose toolchain-goose test clean
all: test

# dist-goose fetches the pinned release and REFUSES any archive whose sha256 is
# not the pin's: the archive is checked before it is unpacked, so a wrong
# download never reaches dist/.
dist-goose:
	@mkdir -p build/dist-goose dist
	@curl -fsSL -o build/dist-goose/$(GOOSE_TAR) $(GOOSE_URL)
	@got=$$(sha256sum build/dist-goose/$(GOOSE_TAR) | cut -d' ' -f1); \
	if [ "$$got" != "$(GOOSE_SHA)" ]; then \
		echo "dist-goose REFUSES: $(GOOSE_TAR) sha256 $$got is not the pin $(GOOSE_SHA)"; \
		rm -f build/dist-goose/$(GOOSE_TAR); exit 1; fi
	@tar -xzf build/dist-goose/$(GOOSE_TAR) -C dist
	@echo "dist-goose: goose $(GOOSE_VERSION) at $(GOOSE_DIST) sha256 $(GOOSE_SHA)"

# toolchain-goose refuses, by name, a pin that does not resolve: $(GOOSE) must
# be an executable (a path, or a name on PATH).
toolchain-goose:
	@if ! command -v "$(GOOSE)" >/dev/null 2>&1; then \
		echo "toolchain-goose REFUSES: GOOSE=$(GOOSE) does not resolve; run make dist-goose (or set GOOSE)"; exit 1; fi

# test: the runner over test/$(T)/ (or every test directory). A missing or
# empty test/<name>/ fails, naming it: never a skip.
test: toolchain-goose
	@sh tools/run_tests.sh $(T)

clean:
	rm -rf build

-include make/*.mk

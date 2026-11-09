# Makefile -- serialize.goose (DESIGN.md, (g) THE RUNNER).
#
# Goose v2026.2, pinned (aardappel/goose tag v2026.2, commit 7ad96d6d47f9).
# To populate dist/ (gitignored), run `make dist-goose` once. The archive
# follows uname -s and uname -m. The linux-x64 url and checksum stay the pin
# below. Darwin uses the published macos tarball of the same tag. Any other
# host is refused before a download.
#   url:    https://github.com/aardappel/goose/releases/download/v2026.2/goose-v2026.2-linux-x64.tar.gz
#   sha256: f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c
#   untarred into dist/goose-v2026.2-<arch>/ (goose, stdlib/, tcclib/)
#
# make test          run every test/*/*_test.goose
# make test T=<name> run the files of test/<name>/ only
#
# A later card adds its own targets in its own make/<card>.mk, included below,
# so no two cards edit this file.

GOOSE_VERSION := v2026.2

# Archive for this host. linux-x64 keeps the url and checksum above.
GOOSE_UNAME_S := $(shell uname -s)
GOOSE_UNAME_M := $(shell uname -m)
GOOSE_ARCH :=
GOOSE_SHA :=
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Linux:x86_64)
GOOSE_ARCH := linux-x64
GOOSE_SHA := f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c
endif
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Linux:amd64)
GOOSE_ARCH := linux-x64
GOOSE_SHA := f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c
endif
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Darwin:arm64)
GOOSE_ARCH := macos-arm64
GOOSE_SHA := d945c8cc1ce35f964ebde9a9e0a40e62533ff55010ed30bf2412af87aa44552a
endif
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Darwin:aarch64)
GOOSE_ARCH := macos-arm64
GOOSE_SHA := d945c8cc1ce35f964ebde9a9e0a40e62533ff55010ed30bf2412af87aa44552a
endif
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Darwin:x86_64)
GOOSE_ARCH := macos-x64
GOOSE_SHA := 341053fb7122c2871f9bf1e8caa19ff45e96549b27804dac0c62d2e45974e649
endif
ifeq ($(GOOSE_UNAME_S):$(GOOSE_UNAME_M),Darwin:amd64)
GOOSE_ARCH := macos-x64
GOOSE_SHA := 341053fb7122c2871f9bf1e8caa19ff45e96549b27804dac0c62d2e45974e649
endif

GOOSE_TAR  := goose-$(GOOSE_VERSION)-$(GOOSE_ARCH).tar.gz
GOOSE_URL  := https://github.com/aardappel/goose/releases/download/$(GOOSE_VERSION)/$(GOOSE_TAR)
GOOSE_DIST := $(CURDIR)/dist/goose-$(GOOSE_VERSION)-$(GOOSE_ARCH)
GOOSE        ?= $(GOOSE_DIST)/goose
export GOOSE

.PHONY: all dist-goose toolchain-goose test clean
all: test

# dist-goose selects the pinned release for this host and REFUSES any archive
# whose sha256 is not that pin. The check runs before unpack, so a wrong
# download never reaches dist/. A host with no published archive is refused
# before the download. The checker is sha256sum -c, or shasum -a 256 -c when
# sha256sum is absent (the same fallback as make/fuzz.mk).
dist-goose:
	@set -eu; \
	os=$$(uname -s); arch=$$(uname -m); \
	case "$$os:$$arch" in \
		Linux:x86_64|Linux:amd64) name=linux-x64; sha=f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c ;; \
		Darwin:arm64|Darwin:aarch64) name=macos-arm64; sha=d945c8cc1ce35f964ebde9a9e0a40e62533ff55010ed30bf2412af87aa44552a ;; \
		Darwin:x86_64|Darwin:amd64) name=macos-x64; sha=341053fb7122c2871f9bf1e8caa19ff45e96549b27804dac0c62d2e45974e649 ;; \
		*) echo "dist-goose REFUSES: no goose $(GOOSE_VERSION) archive for $$os/$$arch"; exit 1 ;; \
	esac; \
	if [ "$(GOOSE_ARCH)" != "$$name" ] || [ "$(GOOSE_SHA)" != "$$sha" ]; then \
		echo "dist-goose REFUSES: no goose $(GOOSE_VERSION) archive for $$os/$$arch"; exit 1; \
	fi; \
	archive=goose-$(GOOSE_VERSION)-$$name.tar.gz; \
	url=https://github.com/aardappel/goose/releases/download/$(GOOSE_VERSION)/$$archive; \
	mkdir -p build/dist-goose dist; \
	curl -fsSL -o "build/dist-goose/$$archive" "$$url"; \
	if command -v sha256sum >/dev/null 2>&1; then \
		printf '%s  %s\n' "$$sha" "build/dist-goose/$$archive" | sha256sum -c -; \
	else \
		printf '%s  %s\n' "$$sha" "build/dist-goose/$$archive" | shasum -a 256 -c -; \
	fi || { \
		echo "dist-goose REFUSES: $$archive sha256 is not the pin $$sha"; \
		rm -f "build/dist-goose/$$archive"; exit 1; }; \
	tar -xzf "build/dist-goose/$$archive" -C dist; \
	echo "dist-goose: goose $(GOOSE_VERSION) at $(CURDIR)/dist/goose-$(GOOSE_VERSION)-$$name sha256 $$sha"

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

# ROADMAP.md is generated from docs/roadmap.sexp (make roadmap, make roadmap-check).
include tools/roadmap/roadmap.mk

-include make/*.mk

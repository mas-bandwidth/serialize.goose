# make/fuzz.mk -- the fuzz differential against serialize.c v2.0.0 (DESIGN.md,
# "The reference"; STANDARD.md, the reference oracle). A functional test: it
# builds programs and spawns processes, so it lives here and not in make test.
#
# make fuzz            the CI smoke: fuzz/host.c (serialize.c v2.0.0 from
#                      .ref/, header-only) generates 2000 programs from its
#                      FIXED seed and drives fuzz/fuzz_driver.goose, built once
#                      with goose build --debug over a staged copy of src/, one
#                      child process per batch of 100 programs, then the three
#                      negative controls below, each of which must go red for
#                      its own reason.
# make fuzz-extended   the nightly run: FUZZ_SEED (printed first, so a red run
#                      replays with it) and FUZZ_DURATION seconds of batches.
#
# Negative controls (the reversed witnesses of this test):
#   range widened   the C side writes one int range one bit wider: the
#                   writers' bytes must differ ("write bytes differ").
#   reader range    the Goose reader's range refusals (int, int64, int128,
#                   fixed) are deleted in a staged copy of src/: a targeted
#                   mutant must be accepted by Goose and refused by C
#                   ("mutant: accept mismatch").
#   wrong reason    the Goose string reader names invalid_utf8 where
#                   embedded_nul is due: the reasons must disagree
#                   ("refusal reason mismatch (C embedded_nul, Goose invalid_utf8)").
# A sabotage whose needle no longer matches src/ fails by name, never a skip.

FUZZ_REF_TAG    := v2.0.0
FUZZ_REF_COMMIT := e11585b0dfbf214ed37c442d5f8b6133fd8b10df
FUZZ_REF        := $(CURDIR)/.ref/serialize.c-$(FUZZ_REF_TAG)
FUZZ_BUILD      := $(CURDIR)/build/fuzz
FUZZ_HOST       := $(FUZZ_BUILD)/host
FUZZ_WORK       := $(FUZZ_BUILD)/work
FUZZ_GOOSE_HOME := $(CURDIR)/build/goose-home
FUZZ_CFLAGS     := -O2 -std=c99 -ffp-contract=off -Wall -Wextra -Werror
FUZZ_SEED       ?= 0x9e3779b97f4a7c15
FUZZ_DURATION   ?= 3600

.PHONY: fuzz fuzz-ref fuzz-host fuzz-driver fuzz-extended

# The oracle, read only: serialize.c at the pin, cloned once into .ref/
# (gitignored). A clone that is not the pinned commit is refused.
fuzz-ref:
	@if [ ! -f "$(FUZZ_REF)/serialize.h" ]; then \
		mkdir -p .ref; \
		git clone -q -c advice.detachedHead=false --branch $(FUZZ_REF_TAG) --depth 1 https://github.com/mas-bandwidth/serialize.c "$(FUZZ_REF)" || \
		{ echo "fuzz REFUSES: cannot clone serialize.c $(FUZZ_REF_TAG) into $(FUZZ_REF)"; exit 1; }; \
	fi
	@got=$$(git -C "$(FUZZ_REF)" rev-parse HEAD); \
	if [ "$$got" != "$(FUZZ_REF_COMMIT)" ]; then \
		echo "fuzz REFUSES: $(FUZZ_REF) is at $$got, not serialize.c $(FUZZ_REF_TAG) $(FUZZ_REF_COMMIT)"; exit 1; fi

fuzz-host: fuzz-ref
	@mkdir -p $(FUZZ_BUILD)
	$(CC) $(FUZZ_CFLAGS) -I$(FUZZ_REF) -o $(FUZZ_HOST) fuzz/host.c

# fuzz_build_driver STAGE EXE: stage src/ and the driver into STAGE (which a
# control may sabotage in between), then goose build it. Zero warnings is
# checked on the unsabotaged build only (a sabotage may leave dead code).
define fuzz_stage
	rm -rf $(1) && mkdir -p $(1) && cp src/*.goose fuzz/fuzz_driver.goose $(1)/
endef
define fuzz_build
	cd $(1) && GOOSE_HOME=$(FUZZ_GOOSE_HOME) $(GOOSE) build fuzz_driver.goose --debug -o $(2) >$(1)/build.log 2>&1 || \
		{ cat $(1)/build.log; echo "fuzz REFUSES: goose build of $(1) failed"; exit 1; }
endef

fuzz-driver: toolchain-goose
	@$(call fuzz_stage,$(FUZZ_BUILD)/stage)
	@$(call fuzz_build,$(FUZZ_BUILD)/stage,$(FUZZ_BUILD)/driver)
	@if grep ': warning: ' $(FUZZ_BUILD)/stage/build.log; then \
		echo "fuzz REFUSES: fuzz/fuzz_driver.goose or src/ builds with warnings (zero warnings)"; exit 1; fi

fuzz: fuzz-host fuzz-driver
	@rm -rf $(FUZZ_WORK) && mkdir -p $(FUZZ_WORK)
	@$(FUZZ_HOST) --driver $(FUZZ_BUILD)/driver --tmp $(FUZZ_WORK)
	@echo "negative control (range widened): the C side writes one int range one bit wider"
	@if $(FUZZ_HOST) --driver $(FUZZ_BUILD)/driver --tmp $(FUZZ_WORK) --negative-control \
		>$(FUZZ_BUILD)/negative.log 2>&1; then \
		echo "negative control (range widened) DID NOT go red"; exit 1; \
	elif ! grep -q 'write bytes differ' $(FUZZ_BUILD)/negative.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/negative.log; then \
		cat $(FUZZ_BUILD)/negative.log; \
		echo "negative control (range widened) went red for the wrong reason"; exit 1; \
	else \
		echo "negative control (range widened): RED as required ($$(grep -m1 'write bytes differ' $(FUZZ_BUILD)/negative.log))"; \
	fi
	@echo "negative control (reader range): the Goose reader's range refusals are deleted"
	@$(call fuzz_stage,$(FUZZ_BUILD)/stage-norange)
	@cd $(FUZZ_BUILD)/stage-norange && for pair in \
		'serialize_int.goose|if offset > (max as! u32) - (min as! u32)' \
		'serialize_int.goose|if offset > (max as! u64) - (min as! u64)' \
		'serialize_int128.goose|if serialize_u128_compare(offset, span) > 0' \
		'serialize_fixed.goose|if fixed_u128_compare(offset, span) > 0'; do \
		f=$${pair%%|*}; needle=$${pair#*|}; \
		grep -qF "$$needle" $$f || { echo "reader range control: the needle '$$needle' no longer matches $$f"; exit 1; }; \
		awk -v n="$$needle" '{ i = index($$0, n); while (i > 0) { $$0 = substr($$0, 1, i - 1) "if false" substr($$0, i + length(n)); i = index($$0, n) } print }' $$f >$$f.tmp && mv $$f.tmp $$f; \
	done
	@$(call fuzz_build,$(FUZZ_BUILD)/stage-norange,$(FUZZ_BUILD)/driver-norange)
	@if $(FUZZ_HOST) --driver $(FUZZ_BUILD)/driver-norange --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/reader.log 2>&1; then \
		echo "negative control (reader range) DID NOT go red"; exit 1; \
	elif ! grep -q 'mutant: accept mismatch' $(FUZZ_BUILD)/reader.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/reader.log; then \
		cat $(FUZZ_BUILD)/reader.log; \
		echo "negative control (reader range) went red for the wrong reason"; exit 1; \
	else \
		echo "negative control (reader range): RED as required ($$(grep -m1 'mutant: accept mismatch' $(FUZZ_BUILD)/reader.log))"; \
	fi
	@echo "negative control (wrong reason): the Goose reader names invalid_utf8 where embedded_nul is due"
	@$(call fuzz_stage,$(FUZZ_BUILD)/stage-reason)
	@cd $(FUZZ_BUILD)/stage-reason && \
		needle='guard payload[i] != 0 else { return serialize_fail(s, SERIALIZE_ERROR_EMBEDDED_NUL); }' && \
		grep -qF "$$needle" serialize_bytes.goose || { echo "wrong reason control: the needle no longer matches serialize_bytes.goose"; exit 1; } && \
		awk -v n="$$needle" '{ i = index($$0, n); if (i > 0) { sub(/SERIALIZE_ERROR_EMBEDDED_NUL/, "SERIALIZE_ERROR_INVALID_UTF8") } print }' serialize_bytes.goose >serialize_bytes.goose.tmp && \
		mv serialize_bytes.goose.tmp serialize_bytes.goose
	@$(call fuzz_build,$(FUZZ_BUILD)/stage-reason,$(FUZZ_BUILD)/driver-reason)
	@if $(FUZZ_HOST) --driver $(FUZZ_BUILD)/driver-reason --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/reason.log 2>&1; then \
		echo "negative control (wrong reason) DID NOT go red"; exit 1; \
	elif ! grep -q 'refusal reason mismatch (C embedded_nul, Goose invalid_utf8)' $(FUZZ_BUILD)/reason.log; then \
		cat $(FUZZ_BUILD)/reason.log; \
		echo "negative control (wrong reason) went red for the wrong reason"; exit 1; \
	else \
		echo "negative control (wrong reason): RED as required ($$(grep -m1 'refusal reason mismatch' $(FUZZ_BUILD)/reason.log))"; \
	fi
	@rm -rf $(FUZZ_WORK) && mkdir -p $(FUZZ_WORK)

# The nightly extended run (.github/workflows/nightly-fuzz.yml). A red run
# keeps its failing batch under build/fuzz/work/ and prints the seed.
fuzz-extended: fuzz-host fuzz-driver
	@mkdir -p $(FUZZ_WORK)
	@$(FUZZ_HOST) --driver $(FUZZ_BUILD)/driver --tmp $(FUZZ_WORK) --seed $(FUZZ_SEED) --duration $(FUZZ_DURATION)

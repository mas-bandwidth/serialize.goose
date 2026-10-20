# make/fuzz.mk -- the fuzz differential target (JOB.md, THE TASK).
#
# fuzz stages build/fuzz/ with src/, fuzz/ and .ref/serialize.c at the pin,
# then runs the Goose program that links serialize.c through fuzz/host.c.
# The negative control enables a test-only switch that widens one int range
# on the C side; it must exit nonzero.

.PHONY: fuzz

FUZZ_STAGE := $(CURDIR)/build/fuzz

fuzz: toolchain-goose
	@if [ ! -f "$(CURDIR)/.ref/serialize.c/serialize.h" ]; then \
		echo "fuzz REFUSES: .ref/serialize.c is missing; clone serialize.c at v1.11.2 into .ref/serialize.c"; exit 1; fi
	@rm -rf "$(FUZZ_STAGE)"; mkdir -p "$(FUZZ_STAGE)"
	@cp $(CURDIR)/src/*.goose "$(FUZZ_STAGE)"/
	@cp $(CURDIR)/fuzz/*.goose $(CURDIR)/fuzz/*.c $(CURDIR)/fuzz/*.build "$(FUZZ_STAGE)"/
	@cp $(CURDIR)/.ref/serialize.c/serialize.c $(CURDIR)/.ref/serialize.c/serialize.h "$(FUZZ_STAGE)"/
	@echo "RUN TestDifferentialAgainstSerializeC"
	@cd "$(FUZZ_STAGE)" && GOOSE_HOME=$(CURDIR)/build/goose-home $(GOOSE) run differential.goose
	@echo "--- PASS TestDifferentialAgainstSerializeC"
	@echo "RUN TestDifferentialAgainstSerializeC (negative control)"
	@if cd "$(FUZZ_STAGE)" && GOOSE_HOME=$(CURDIR)/build/goose-home $(GOOSE) run negative.goose >negative.out 2>&1; then \
		echo "--- FAIL negative control stayed green"; cat "$(FUZZ_STAGE)/negative.out"; exit 1; \
	else \
		echo "--- PASS negative control (red as required)"; \
	fi

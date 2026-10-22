# make/witnesses.mk -- the reversed witnesses: each row of tools/witnesses.sh
# deletes one rule in a scratch copy of src/ and the suite must go red.

.PHONY: witnesses

witnesses: toolchain-goose
	@sh tools/witnesses.sh

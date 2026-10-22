# make/controls.mk -- the negative controls: each row of tools/controls.sh
# deletes one refusal rule in a scratch copy of src/, and the real corpus must
# then fail exactly the vectors conformance-controls/<rule>.expected names.

.PHONY: controls

controls: toolchain-goose
	@sh tools/controls.sh

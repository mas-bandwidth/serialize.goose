#!/bin/sh
# tools/revendor.sh <ref> -- re-vendor the standard from mas-bandwidth/serialize.
#
# Copies STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/
# VERBATIM from the reference at <ref>, a tag or a full commit sha (DESIGN.md, "The vendored
# standard"), then prints the diff against the tree. It never edits anything
# else: the corpus pin in DESIGN.md and SERIALIZE_TAG in ci.yml are changed by
# hand, in the same commit, and make check-ci holds them equal.
set -eu

if [ $# -ne 1 ]; then
	echo "usage: tools/revendor.sh <ref>   (a tag such as v2.0.0, or a full commit sha)"
	exit 2
fi
tag=$1
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$root/build/revendor
rm -rf "$scratch"
mkdir -p "$root/build"
git init --quiet "$scratch"
git -C "$scratch" fetch --quiet --depth 1 https://github.com/mas-bandwidth/serialize.git "$tag"
git -C "$scratch" checkout --quiet FETCH_HEAD

rm -rf "$root/conformance" "$root/conformance-controls"
cp -R "$scratch/conformance" "$root/conformance"
cp -R "$scratch/conformance-controls" "$root/conformance-controls"
cp "$scratch/STANDARD.md" "$scratch/IMPLEMENTING.md" "$root"/

cd "$root"
git status --short -- STANDARD.md IMPLEMENTING.md conformance conformance-controls
echo "re-vendored from mas-bandwidth/serialize $tag ($(git -C "$scratch" rev-parse HEAD))"

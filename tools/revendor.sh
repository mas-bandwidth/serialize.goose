#!/bin/sh
# tools/revendor.sh <tag> -- re-vendor the standard from mas-bandwidth/serialize.
#
# Copies STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/
# VERBATIM from a clone of the reference at <tag> (DESIGN.md, "The vendored
# standard"), then prints the diff against the tree. It never edits anything
# else: the corpus pin in DESIGN.md and SERIALIZE_TAG in ci.yml are changed by
# hand, in the same commit, and make check-ci holds them equal.
set -eu

if [ $# -ne 1 ]; then
	echo "usage: tools/revendor.sh <tag>   (for example v2.0.0)"
	exit 2
fi
tag=$1
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$root/build/revendor
rm -rf "$scratch"
mkdir -p "$root/build"
git clone --quiet --depth 1 --branch "$tag" https://github.com/mas-bandwidth/serialize.git "$scratch"

rm -rf "$root/conformance" "$root/conformance-controls"
cp -R "$scratch/conformance" "$root/conformance"
cp -R "$scratch/conformance-controls" "$root/conformance-controls"
cp "$scratch/STANDARD.md" "$scratch/IMPLEMENTING.md" "$root"/

cd "$root"
git status --short -- STANDARD.md IMPLEMENTING.md conformance conformance-controls
echo "re-vendored from mas-bandwidth/serialize $tag ($(git -C "$scratch" rev-parse HEAD))"

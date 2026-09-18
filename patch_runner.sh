#!/bin/bash
#
# Clones the upstream Github actions/runner repo and applies the
# modifications necessary to to turn it into a RISC-V-capable runner, 
# then copies the patched tree into a runner_src/ directory next to 
# this script (overwriting any files that also exist upstream; 
# everything else is left untouched).
#
# Usage: ./patch_runner.sh [branch-or-tag-of-actions/runner]
#        (defaults to the upstream default branch)

set -euo pipefail

RUNNER_SRC="$(dirname "${BASH_SOURCE[0]}")/runner_src"
mkdir -p $RUNNER_SRC
DEST_DIR="$(cd $RUNNER_SRC && pwd)"
UPSTREAM_URL="https://github.com/actions/runner.git"
REF="${1:-}"

command -v git > /dev/null || { echo "Failed: git is required" >&2; exit 1; }
command -v python3 > /dev/null || { echo "Failed: python3 is required" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

REPO="$TMP_DIR/runner"

if [ -n "$REF" ]; then
    echo "Cloning ${UPSTREAM_URL} @ ${REF} into ${TMP_DIR} ..."
    git clone --depth 1 --branch "$REF" "$UPSTREAM_URL" "$REPO"
else
    echo "Cloning ${UPSTREAM_URL} (default branch) into ${TMP_DIR} ..."
    git clone --depth 1 "$UPSTREAM_URL" "$REPO"
fi

echo "Applying RISC-V patch ..."
python3 ./apply_changes_for_riscv.py $REPO

echo "Copying patched tree into ${DEST_DIR} (excluding .git) ..."
if command -v rsync > /dev/null; then
    rsync -a "$REPO"/src "$DEST_DIR"/
    rsync -a "$REPO"/scripts "$DEST_DIR"/
    # this is necessary for the dotnet build to run (and explicitly untracked in the .gitignore)
    rsync -a "$REPO"/.git "$DEST_DIR"/
else
    find "$REPO" -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -a {} "$DEST_DIR"/ \;
fi

echo "Done. ${DEST_DIR} now reflects $( [ -n "$REF" ] && echo "$REF" || echo "the upstream default branch" ) of actions/runner with the RISC-V patch applied."

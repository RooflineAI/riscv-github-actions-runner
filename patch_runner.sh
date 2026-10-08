#!/bin/bash
#
# Clones the upstream Github actions/runner repo and applies the
# modifications necessary to turn it into a RISC-V-capable runner, then
# copies the patched tree into runner_src_<tag>/ next to this script.
#
# <tag> is <first 12 chars of the upstream commit>-<8 chars of a fingerprint
# of the three scripts in this repo>. The same upstream commit patched by the
# same scripts therefore always lands in the same directory, so a caller can
# tell from the name alone whether a build for it already exists. The
# directory also holds UPSTREAM_COMMIT (full upstream commit hash) and
# PATCH_FINGERPRINT; compile_runner.sh copies both into the runner package.
#
# The last line printed is RUNNER_SRC_DIR=<absolute path of that directory>.
#
# Usage: ./patch_runner.sh [branch-or-tag-of-actions/runner]
#        (defaults to the upstream default branch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

UPSTREAM_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
PATCH_FINGERPRINT="$(
    cat "$SCRIPT_DIR/apply_changes_for_riscv.py" "$SCRIPT_DIR/patch_runner.sh" "$SCRIPT_DIR/compile_runner.sh" \
        | { sha256sum 2>/dev/null || shasum -a 256; } \
        | cut -c1-8
)"
DEST_DIR="$SCRIPT_DIR/runner_src_${UPSTREAM_COMMIT:0:12}-${PATCH_FINGERPRINT}"

echo "Applying RISC-V patch ..."
(cd "$SCRIPT_DIR" && python3 ./apply_changes_for_riscv.py "$REPO")

echo "Copying patched tree into ${DEST_DIR} (excluding .git) ..."
mkdir -p "$DEST_DIR"
if command -v rsync > /dev/null; then
    rsync -a "$REPO"/src "$DEST_DIR"/
    rsync -a "$REPO"/scripts "$DEST_DIR"/
    # this is necessary for the dotnet build to run (and explicitly untracked in the .gitignore)
    rsync -a "$REPO"/.git "$DEST_DIR"/
else
    find "$REPO" -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -a {} "$DEST_DIR"/ \;
fi

printf '%s\n' "$UPSTREAM_COMMIT" > "$DEST_DIR/UPSTREAM_COMMIT"
printf '%s\n' "$PATCH_FINGERPRINT" > "$DEST_DIR/PATCH_FINGERPRINT"

echo "Done. ${DEST_DIR} now reflects $( [ -n "$REF" ] && echo "$REF" || echo "the upstream default branch" ) of actions/runner (${UPSTREAM_COMMIT}) with the RISC-V patch applied."
echo "RUNNER_SRC_DIR=${DEST_DIR}"

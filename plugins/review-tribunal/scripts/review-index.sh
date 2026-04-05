#!/usr/bin/env bash
# review-index.sh — Generates an index file mapping each changed file to its line number in a patch.
#
# Usage:
#   review-index.sh -p <patch_path> -o <output_path>
#
# Reads the patch at <patch_path> and writes an index to <output_path>.
# Each line of the index has the format:
#   diff --git a/<path> b/<path>  <line_number>
#
# Subagents use this index to seek directly to a file's hunk in the patch
# rather than scanning the full diff from the top.
#
# Progress and line count go to stderr. Exits non-zero on failure.

set -euo pipefail

usage() {
    echo "Usage: $0 -p <patch_path> -o <output_path>" >&2
    exit 1
}

PATCH_PATH=""
OUTPUT_PATH=""

while getopts ":p:o:" opt; do
    case $opt in
        p) PATCH_PATH="$OPTARG" ;;
        o) OUTPUT_PATH="$OPTARG" ;;
        *) usage ;;
    esac
done

[[ -z "$PATCH_PATH" ]]  && { echo "Error: -p <patch_path> is required" >&2; exit 1; }
[[ -z "$OUTPUT_PATH" ]] && { echo "Error: -o <output_path> is required" >&2; exit 1; }
[[ ! -f "$PATCH_PATH" ]] && { echo "Error: patch file not found: '$PATCH_PATH'" >&2; exit 1; }

# Ensure output directory exists
OUT_DIR="$(dirname "$OUTPUT_PATH")"
if [[ -n "$OUT_DIR" && ! -d "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
fi

echo "Reading patch..." >&2

# Build index: for each "diff --git" header line, emit the header text + two spaces + 1-based line number.
# Two spaces match the PowerShell script's output format that subagents expect.
awk '/^diff --git / { print $0 "  " NR }' "$PATCH_PATH" > "$OUTPUT_PATH"

COUNT=$(wc -l < "$OUTPUT_PATH")
echo "Index written: $OUTPUT_PATH ($COUNT file(s) indexed)" >&2

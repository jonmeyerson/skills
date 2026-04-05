#!/usr/bin/env bash
# review-patch.sh — Generates a unified diff patch file for a review tribunal session.
#
# Usage:
#   review-patch.sh -m branch    -o <output_path> -b <base> -h <head>
#   review-patch.sh -m uncommitted -o <output_path> -B <branch>
#
# Writes the git diff to <output_path> and prints changed file paths to stdout,
# one per line. Progress messages go to stderr. Exits non-zero on failure.

set -euo pipefail

usage() {
    echo "Usage:" >&2
    echo "  $0 -m branch     -o <output_path> -b <base> -h <head>" >&2
    echo "  $0 -m uncommitted -o <output_path> -B <branch>" >&2
    exit 1
}

MODE=""
OUTPUT_PATH=""
BASE=""
HEAD=""
BRANCH=""

while getopts ":m:o:b:h:B:" opt; do
    case $opt in
        m) MODE="$OPTARG" ;;
        o) OUTPUT_PATH="$OPTARG" ;;
        b) BASE="$OPTARG" ;;
        h) HEAD="$OPTARG" ;;
        B) BRANCH="$OPTARG" ;;
        *) usage ;;
    esac
done

# Validate mode
if [[ "$MODE" != "branch" && "$MODE" != "uncommitted" ]]; then
    echo "Error: -m must be 'branch' or 'uncommitted'" >&2
    exit 1
fi
if [[ -z "$OUTPUT_PATH" ]]; then
    echo "Error: -o <output_path> is required" >&2
    exit 1
fi

# Validate mode-specific args
if [[ "$MODE" == "branch" ]]; then
    [[ -z "$BASE" ]] && { echo "Error: -b <base> is required in branch mode" >&2; exit 1; }
    [[ -z "$HEAD" ]] && { echo "Error: -h <head> is required in branch mode" >&2; exit 1; }
    [[ "$BASE" == "$HEAD" ]] && { echo "Error: base and head must not be the same ref ('$BASE')" >&2; exit 1; }
fi
if [[ "$MODE" == "uncommitted" ]]; then
    [[ -z "$BRANCH" ]] && { echo "Error: -B <branch> is required in uncommitted mode" >&2; exit 1; }
fi

# Ensure output directory exists
OUT_DIR="$(dirname "$OUTPUT_PATH")"
if [[ -n "$OUT_DIR" && ! -d "$OUT_DIR" ]]; then
    echo "Creating output directory: $OUT_DIR" >&2
    mkdir -p "$OUT_DIR"
fi

# Get changed file list
echo "Listing changed files..." >&2
if [[ "$MODE" == "branch" ]]; then
    git diff "${BASE}..${HEAD}" --name-only
else
    git diff --staged --name-only
fi

# Write patch (LF line endings)
echo "Writing patch to $OUTPUT_PATH..." >&2
if [[ "$MODE" == "branch" ]]; then
    git diff "${BASE}..${HEAD}" | tr -d '\r' > "$OUTPUT_PATH"
else
    git diff --staged | tr -d '\r' > "$OUTPUT_PATH"
fi

echo "Done." >&2

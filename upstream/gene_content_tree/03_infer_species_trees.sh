#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
Usage:
  05_infer_species_trees.sh --matrix-dir DIR --out-dir DIR [--outgroup TAXON] [--threads AUTO] [--bootstraps 1000] [--model MK+R+FO+ASC]
EOF
}
MATRIX_DIR=""; OUT_DIR=""; OUTGROUP=""; THREADS="AUTO"; BOOTSTRAPS=1000; MODEL="MK+R+FO+ASC"; IQTREE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix-dir) MATRIX_DIR="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --outgroup) OUTGROUP="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --bootstraps) BOOTSTRAPS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --iqtree) IQTREE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MATRIX_DIR" && -n "$OUT_DIR" ]] || { usage >&2; exit 2; }
if [[ -z "$IQTREE" ]]; then
  for x in iqtree2 iqtree3 iqtree; do
    if command -v "$x" >/dev/null 2>&1; then IQTREE="$x"; break; fi
  done
fi
[[ -n "$IQTREE" ]] || { echo "Could not find iqtree2, iqtree3, or iqtree" >&2; exit 1; }
mkdir -p "$OUT_DIR"
mapfile -t matrices < <(find "$MATRIX_DIR" -type f -name '*.phy' | sort)
[[ ${#matrices[@]} -gt 0 ]] || { echo "No .phy matrices found under $MATRIX_DIR" >&2; exit 1; }
for matrix in "${matrices[@]}"; do
  rel="${matrix#"$MATRIX_DIR"/}"
  dataset="${rel%/*}"
  stem="$(basename "$matrix" .phy)"
  d="$OUT_DIR/$dataset"; mkdir -p "$d"
  prefix="$d/$stem"
  cmd=("$IQTREE" -s "$matrix" -st MORPH -m "$MODEL" -b "$BOOTSTRAPS" -nt "$THREADS" -pre "$prefix")
  [[ -z "$OUTGROUP" ]] || cmd+=( -o "$OUTGROUP" )
  printf 'Running:' >&2; printf ' %q' "${cmd[@]}" >&2; printf '\n' >&2
  "${cmd[@]}"
done

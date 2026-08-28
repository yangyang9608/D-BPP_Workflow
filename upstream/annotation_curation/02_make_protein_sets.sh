#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  02_make_protein_sets.sh --manifest species.tsv --curated-dir DIR --out-dir DIR [--thresholds 0,50,100,150]
EOF
}
MANIFEST=""; CURATED_DIR=""; OUT_DIR=""; THRESHOLDS="0,50,100,150"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --curated-dir) CURATED_DIR="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --thresholds) THRESHOLDS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MANIFEST" && -n "$CURATED_DIR" && -n "$OUT_DIR" ]] || { usage >&2; exit 2; }
command -v seqkit >/dev/null 2>&1 || { echo "Required executable not found: seqkit" >&2; exit 1; }
mkdir -p "$OUT_DIR"

IFS=',' read -r -a thresholds <<< "$THRESHOLDS"
for t in "${thresholds[@]}"; do
  [[ "$t" =~ ^[0-9]+$ ]] || { echo "Invalid threshold: $t" >&2; exit 1; }
  if [[ "$t" -eq 0 ]]; then name="all"; else name="min${t}aa"; fi
  mkdir -p "$OUT_DIR/$name"
done

while IFS=$'\t' read -r species genome gff rest; do
  [[ -z "${species:-}" || "$species" == "species" || "$species" =~ ^# ]] && continue
  input="$CURATED_DIR/$species/$species.faa"
  [[ -s "$input" ]] || { echo "Curated protein file missing/empty: $input" >&2; exit 1; }
  for t in "${thresholds[@]}"; do
    if [[ "$t" -eq 0 ]]; then
      cp "$input" "$OUT_DIR/all/$species.faa"
    else
      mkdir -p "$OUT_DIR/min${t}aa"
      seqkit seq -m "$t" "$input" -o "$OUT_DIR/min${t}aa/$species.faa" >/dev/null
    fi
  done
done < "$MANIFEST"

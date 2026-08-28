#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
Usage:
  04_build_matrices.sh --gene-count-manifest gene_count_tables.tsv --out-dir DIR
EOF
}
MANIFEST=""; OUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gene-count-manifest) MANIFEST="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MANIFEST" && -n "$OUT_DIR" ]] || { usage >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"
while IFS=$'\t' read -r dataset table rest; do
  [[ -z "${dataset:-}" || "$dataset" == "dataset" || "$dataset" =~ ^# ]] && continue
  [[ -s "$table" ]] || { echo "Gene-count table missing/empty: $table" >&2; exit 1; }
  d="$OUT_DIR/$dataset"; mkdir -p "$d"
  python3 "$SCRIPT_DIR/scripts/build_gene_content_matrix.py" --gene-count "$table" --out-prefix "$d/all_families" >/dev/null
done < "$MANIFEST"

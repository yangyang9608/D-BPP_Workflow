#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
Usage:
  01_run_orthofinder.sh --sets-dir DIR --out-dir DIR [--threads 8] [--analysis-threads 1]
EOF
}
SETS_DIR=""; OUT_DIR=""; THREADS=8; ANALYSIS_THREADS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sets-dir) SETS_DIR="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --analysis-threads) ANALYSIS_THREADS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$SETS_DIR" && -n "$OUT_DIR" ]] || { usage >&2; exit 2; }
command -v orthofinder >/dev/null 2>&1 || { echo "Required executable not found: orthofinder" >&2; exit 1; }
mkdir -p "$OUT_DIR"
manifest="$OUT_DIR/gene_count_tables.tsv"
printf 'dataset\tgene_count_table\n' > "$manifest"

shopt -s nullglob
for set_dir in "$SETS_DIR"/*; do
  [[ -d "$set_dir" ]] || continue
  faa=("$set_dir"/*.faa)
  [[ ${#faa[@]} -ge 3 ]] || continue
  name="$(basename "$set_dir")"
  target="$OUT_DIR/$name"
  [[ ! -e "$target" ]] || { echo "OrthoFinder output already exists: $target" >&2; exit 1; }
  echo "[$name] running OrthoFinder" >&2
  orthofinder -f "$set_dir" -t "$THREADS" -a "$ANALYSIS_THREADS" -o "$target"
  gene_count="$(find "$target" -type f -name 'Orthogroups.GeneCount.tsv' -print | head -n 1)"
  [[ -n "$gene_count" && -s "$gene_count" ]] || { echo "Could not locate Orthogroups.GeneCount.tsv under $target" >&2; exit 1; }
  printf '%s\t%s\n' "$name" "$gene_count" >> "$manifest"
done

[[ $(wc -l < "$manifest") -gt 1 ]] || { echo "No protein-set directories containing >=3 .faa files were found" >&2; exit 1; }
echo "$manifest"

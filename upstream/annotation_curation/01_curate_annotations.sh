#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  01_curate_annotations.sh --manifest species.tsv --out-dir DIR [--strand-aware]

Manifest columns (tab-delimited):
  species  genome_fasta  annotation_gff3
EOF
}

MANIFEST=""
OUT_DIR=""
STRAND_AWARE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --strand-aware) STRAND_AWARE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MANIFEST" && -n "$OUT_DIR" ]] || { usage >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

for cmd in agat_convert_sp_gxf2gxf.pl agat_sp_keep_longest_isoform.pl agat_sp_filter_feature_from_keep_list.pl bedtools gffread python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required executable not found: $cmd" >&2; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

while IFS=$'\t' read -r species genome gff rest; do
  [[ -z "${species:-}" ]] && continue
  [[ "$species" == "species" ]] && continue
  [[ "$species" =~ ^# ]] && continue
  [[ -z "${rest:-}" ]] || { echo "Manifest row for $species has more than 3 columns" >&2; exit 1; }
  [[ "$species" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid species label: $species" >&2; exit 1; }
  [[ -f "$genome" ]] || { echo "Genome not found for $species: $genome" >&2; exit 1; }
  [[ -f "$gff" ]] || { echo "Annotation not found for $species: $gff" >&2; exit 1; }

  d="$OUT_DIR/$species"
  mkdir -p "$d"
  echo "[$species] AGAT parsing/repair" >&2
  agat_convert_sp_gxf2gxf.pl --gff "$gff" --output "$d/01_agat_repaired.gff3"

  echo "[$species] retain longest coding isoform" >&2
  agat_sp_keep_longest_isoform.pl --gff "$d/01_agat_repaired.gff3" --output "$d/02_longest_isoform.gff3"

  echo "[$species] construct CDS spans and overlap components" >&2
  python3 "$SCRIPT_DIR/scripts/gff_to_cds_bed.py" --gff "$d/02_longest_isoform.gff3" > "$d/03_cds_spans.bed"
  bedtools sort -i "$d/03_cds_spans.bed" > "$d/03_cds_spans.sorted.bed"
  if [[ "$STRAND_AWARE" -eq 1 ]]; then
    bedtools cluster -s -i "$d/03_cds_spans.sorted.bed" > "$d/04_cds_spans.clustered.bed"
  else
    bedtools cluster -i "$d/03_cds_spans.sorted.bed" > "$d/04_cds_spans.clustered.bed"
  fi
  python3 "$SCRIPT_DIR/scripts/select_cluster_representatives.py" \
    --clustered-bed "$d/04_cds_spans.clustered.bed" \
    --keep-list "$d/05_keep_transcripts.txt" \
    --summary "$d/05_overlap_clusters.tsv"

  echo "[$species] filter annotation to selected representatives" >&2
  agat_sp_filter_feature_from_keep_list.pl \
    --gff "$d/02_longest_isoform.gff3" \
    --keep_list "$d/05_keep_transcripts.txt" \
    --output "$d/$species.curated.gff3"

  echo "[$species] extract CDS/protein sequences" >&2
  gffread "$d/$species.curated.gff3" -g "$genome" \
    -x "$d/06_raw.cds.fa" -y "$d/06_raw.faa"

  python3 "$SCRIPT_DIR/scripts/filter_cds_protein.py" \
    --cds "$d/06_raw.cds.fa" \
    --protein "$d/06_raw.faa" \
    --out-cds "$d/$species.cds.fa" \
    --out-protein "$d/$species.faa" \
    --id-map "$d/$species.id_map.tsv" \
    --summary "$d/$species.coding_filter_summary.tsv" \
    --prefix "$species"

done < "$MANIFEST"

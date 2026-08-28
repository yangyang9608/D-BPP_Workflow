#!/usr/bin/env bash

set -o pipefail

usage() {
    local status="${1:-1}"
    echo "Usage: bash $0 (--fasta_dir <fasta_dir> | --vcf_file <vcf_file>) --imap <imap_file> --treelist <treelist_file> [--prefix <output_prefix>] [--cutoff <value>]"
    echo ""
    echo "Required parameters (choose one input type):"
    echo "  --fasta_dir <dir>     Directory containing locus FASTA files (.fa, .fas, .fasta)"
    echo "  --vcf_file <file>     VCF file"

    echo "Other Required parameters:"
    echo "  --imap <file>         Individual to species mapping file"
    echo "  --treelist <file>     File containing multiple trees (one per line)"
    echo ""
    echo "Optional parameters:"
    echo "  --cutoff <value>      Cutoff value for p-value (default: 0.01, after Bonferroni correction)"
    echo "  --prefix <prefix>     Output prefix (path will be created if needed; default: D-step/Sig-D)"
    echo ""
    echo "Output:"
    echo "  For each tree in treelist, generates prefix-Tree*.tree and prefix-Tree*.sig-triples containing"
    echo "  all significant triples (after Bonferroni correction) sorted by Dp value in descending order"
    exit "$status"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_value() {
    local option="$1"
    local value="${2-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        die "$option requires a value"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found in PATH"
}

# default values
FILTER_COL="p-value"
CUTOFF="0.01"
PREFIX="D-step/Sig-D"

if [[ $# -eq 0 ]]; then
    usage 1
fi

#########
while [[ $# -gt 0 ]]; do
    case $1 in
        --fasta_dir)
            require_value "$1" "${2-}"
            FAS_DIR="$2"
            shift 2
            ;;
        --vcf_file)
            require_value "$1" "${2-}"
            VCF_FILE="$2"
            shift 2
            ;;
        --imap)
            require_value "$1" "${2-}"
            IMAP_FILE="$2"
            shift 2
            ;;
        --treelist)
            require_value "$1" "${2-}"
            TREELIST_FILE="$2"
            shift 2
            ;;
        --cutoff)
            require_value "$1" "${2-}"
            CUTOFF="$2"
            shift 2
            ;;
        --prefix)
            require_value "$1" "${2-}"
            PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage 1
            ;;
    esac
done


#check Required parameters and files
if [[ -z "$IMAP_FILE" || -z "$TREELIST_FILE" ]]; then
    echo "ERROR: Missing required parameters" >&2
    usage 1
fi

if [[ -n "$FAS_DIR" && -n "$VCF_FILE" ]]; then
    echo "ERROR: Cannot specify both --fasta_dir and --vcf_file" >&2
    usage 1
elif [[ -z "$FAS_DIR" && -z "$VCF_FILE" ]]; then
    echo "ERROR: Must specify either --fasta_dir or --vcf_file" >&2
    usage 1
elif [[ -n "$FAS_DIR" && ! -d "$FAS_DIR" ]]; then
    die "FASTA directory '$FAS_DIR' does not exist"
elif [[ -n "$VCF_FILE" && ! -f "$VCF_FILE" ]]; then
    die "VCF file '$VCF_FILE' does not exist"
fi

for file in "$IMAP_FILE" "$TREELIST_FILE"; do
    if [[ ! -f "$file" ]]; then
        die "Input file '$file' does not exist"
    fi
done

# check cutoff
if ! [[ "$CUTOFF" =~ ^-?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]; then
    die "--cutoff must be numeric (received '$CUTOFF')"
fi
awk -v value="$CUTOFF" 'BEGIN { exit !(value > 0 && value <= 1) }' || \
    die "--cutoff must be greater than 0 and no greater than 1 (received '$CUTOFF')"

#Create the output directory if it does not exist
PREFIX_DIR=$(dirname "$PREFIX")
mkdir -p "$PREFIX_DIR" || die "Failed to create output directory '$PREFIX_DIR'"

require_command Dsuite
require_command nw_display
if [[ -n "$FAS_DIR" ]]; then
    require_command snp-sites
fi


declare -A INDIVIDUALS
declare -A SPECIES
INDIVIDUAL_LIST=()
OUTGROUP_COUNT=0
IMAP_LINE=0
while read -r individual species extra || [[ -n "$individual" ]]; do
    ((IMAP_LINE++))
    [[ -z "$individual" || "$individual" == \#* ]] && continue
    [[ -n "$species" && -z "$extra" ]] || die "Malformed IMAP line $IMAP_LINE; expected exactly two whitespace-delimited columns"
    [[ -z "${INDIVIDUALS[$individual]}" ]] || die "Duplicate individual '$individual' in IMAP file"
    INDIVIDUALS["$individual"]=1
    INDIVIDUAL_LIST+=("$individual")

    if [[ "$species" == "Outgroup" ]]; then
        ((OUTGROUP_COUNT++))
    else
        SPECIES["$species"]=1
    fi
done < "$IMAP_FILE"
TOTAL_INDIVIDUALS=${#INDIVIDUAL_LIST[@]}
N_SPECIES=${#SPECIES[@]}
[[ $TOTAL_INDIVIDUALS -gt 0 ]] || die "IMAP file contains no samples"
[[ $OUTGROUP_COUNT -gt 0 ]] || die "IMAP file must contain at least one sample assigned to species 'Outgroup'"
[[ $N_SPECIES -ge 3 ]] || die "D-statistic analysis requires at least three ingroup species"
N_TRIPLES=$(( N_SPECIES * (N_SPECIES - 1) * (N_SPECIES - 2) / 6 ))


echo "Starting analysis with parameters:"
[[ -n "$FAS_DIR" ]] && echo "  Fasta files: $FAS_DIR"
[[ -n "$VCF_FILE" ]] && echo "  Vcf file: $VCF_FILE"
echo "  IMAP file: $IMAP_FILE" 
echo "  Tree list: $TREELIST_FILE"
echo "  Output prefix: $PREFIX"
echo "  Filter criteria: $FILTER_COL"
echo "  Cutoff value: $CUTOFF"

# function for converting vcf
convert_haploid_to_diploid() {
    local input_vcf="$1"
    local output_vcf="$2"

    awk '
    BEGIN {
        deg_list["M"] = "A,C";
        deg_list["Y"] = "C,T";
        deg_list["R"] = "A,G";
        deg_list["S"] = "C,G";
        deg_list["W"] = "A,T";
        deg_list["K"] = "G,T";
        deg_list["A"] = "A";
        deg_list["C"] = "C";
        deg_list["G"] = "G";
        deg_list["T"] = "T";
        deg_list["*"] = "*";

        OFS = "\t";
    }

    /^#/ {
        print $0;
        next;
    }

    $4 ~ /[VHDB]/ || $5 ~ /[VHDB]/ { next; }

    {
        delete all_bases;       
        delete bases_list;       
        delete base_to_index;    
        delete raw_allele_list; 
        bases_count = 0;

	# record ref/alt base index
        raw_allele_list[0] = $4;
        raw_alt_count = split($5, raw_alt_arr, ",");
        for (i = 1; i <= raw_alt_count; i++) {
            raw_allele_list[i] = raw_alt_arr[i];
        }

	# generate new ref/alt
        ref_alt_str = $4 "," $5;
        raw_base_count = split(ref_alt_str, raw_bases, ",");
        for (i = 1; i <= raw_base_count; i++) {
            curr_base = raw_bases[i];
            if (curr_base == "" || curr_base == "*") continue;

            split_count = split(deg_list[curr_base], ab_split, ",");
            for (s = 1; s <= split_count; s++) {
                b = ab_split[s];
                if (b == "") continue;

                if (!all_bases[b]) {
                    all_bases[b] = 1;
                    bases_list[++bases_count] = b;
                    base_to_index[b] = bases_count - 1; 
                }
            }
        }
        if (bases_count == 0) next;
        new_ref = bases_list[1];                # new REF
        new_alt = "";				# new ALT
        for (i=2; i<=bases_count; i++) {
            new_alt = (new_alt == "") ? bases_list[i] : new_alt "," bases_list[i];
        }
        if (new_alt == "") new_alt = ".";

        printf("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tGT", $1, $2, $3, new_ref, new_alt, $6, $7, $8);
        for (i=10; i<=NF; i++) {
            split($i, sample_fields, ":");
            raw_gt = sample_fields[1];
            new_gt = "./."; 
            if (raw_gt !~ /^[0-9]+$/) {
                printf("\t%s", new_gt);
                continue;
            }
            raw_base = raw_allele_list[raw_gt];
            if (raw_base == "" || raw_base == "*") {
                printf("\t%s", new_gt);
                continue;
            }
            split_count = split(deg_list[raw_base], raw_base_split, ",");
            if (split_count == 1) {
                base_idx = base_to_index[raw_base_split[1]];
                new_gt = base_idx "/" base_idx;
            } else if (split_count == 2) {
                idx1 = base_to_index[raw_base_split[1]];
                idx2 = base_to_index[raw_base_split[2]];
                if (idx1 > idx2) {
                    t = idx1; idx1 = idx2; idx2 = t;
                }
                new_gt = idx1 "/" idx2;
            }

            printf("\t%s", new_gt);
        }
        print "";  
    }
    ' "$input_vcf" > "$output_vcf"
}

# Concatenate multi-locus FASTA files and convert them to VCF.
if [[ -n "$FAS_DIR" ]]; then
    CONCAT_FASTA=$(mktemp "${PREFIX_DIR}/.dbpp-concatenated.XXXXXX.fasta") || die "Could not create a temporary FASTA file"
    TEMP_FASTA=$(mktemp "${PREFIX_DIR}/.dbpp-loci.XXXXXX.fasta") || die "Could not create a temporary FASTA file"
    VCF_FILE_TEMP=$(mktemp "${PREFIX_DIR}/.dbpp-snps.XXXXXX.vcf") || die "Could not create a temporary VCF file"
    GENERATED_VCF=$(mktemp "${PREFIX_DIR}/.dbpp-diploid.XXXXXX.vcf") || die "Could not create a temporary VCF file"
    LOCUS_FASTA=""

    cleanup_fasta_intermediates() {
        rm -f "$CONCAT_FASTA" "$TEMP_FASTA" "$VCF_FILE_TEMP" "$GENERATED_VCF"
        [[ -n "$LOCUS_FASTA" ]] && rm -f "$LOCUS_FASTA"
    }
    trap cleanup_fasta_intermediates EXIT
    
    VALID_LOCUS_COUNT=0
    TOTAL_LOCUS_COUNT=0
    
    for fasta_file in "$FAS_DIR"/*.fasta "$FAS_DIR"/*.fa "$FAS_DIR"/*.fas; do
        if [[ ! -f "$fasta_file" ]]; then
            continue 
        fi
    
        TOTAL_LOCUS_COUNT=$((TOTAL_LOCUS_COUNT + 1))
        LOCUS_NAME=$(basename "$fasta_file")
        
        LOCUS_FASTA=$(mktemp "${PREFIX_DIR}/.dbpp-locus.XXXXXX.fasta") || die "Could not create a temporary locus file"
        awk '
            /^>/ {
                if (seen_header) print ""
                print $0
                seen_header = 1
                next
            }
            seen_header {
                gsub(/[[:space:]]/, "")
                printf "%s", toupper($0)
            }
            END { if (seen_header) print "" }
        ' "$fasta_file" > "$LOCUS_FASTA"

        declare -A PRESENT_INDIVIDUALS=()
        MISSING_COUNT=0
        LOCUS_LENGTH=0

        while IFS= read -r header && IFS= read -r sequence; do
            [[ "$header" == '>'* ]] || die "Malformed FASTA record in '$fasta_file'"
            seq_name="${header#>}"
            seq_name="${seq_name%%[[:space:]]*}"
            [[ -n "$seq_name" ]] || die "Empty FASTA identifier in '$fasta_file'"
            [[ -z "${PRESENT_INDIVIDUALS[$seq_name]}" ]] || die "Duplicate FASTA identifier '$seq_name' in '$fasta_file'"
            [[ -n "$sequence" ]] || die "Empty sequence for '$seq_name' in '$fasta_file'"
            [[ "$sequence" =~ ^[ACGTRYSWKMBDHVN?*-]+$ ]] || die "Unsupported sequence character for '$seq_name' in '$fasta_file'"
            PRESENT_INDIVIDUALS["$seq_name"]=1

            if [[ $LOCUS_LENGTH -eq 0 ]]; then
                LOCUS_LENGTH=${#sequence}
            elif [[ ${#sequence} -ne $LOCUS_LENGTH ]]; then
                die "Sequences are not aligned to a common length in '$fasta_file'"
            fi
        done < "$LOCUS_FASTA"
        
        MISSING_LIST=()
        for individual in "${INDIVIDUAL_LIST[@]}"; do
            if [[ -z "${PRESENT_INDIVIDUALS[$individual]}" ]]; then
                MISSING_COUNT=$((MISSING_COUNT + 1))
                MISSING_LIST+=("$individual")
            fi
        done
        
        if [[ $MISSING_COUNT -eq 0 ]]; then
            VALID_LOCUS_COUNT=$((VALID_LOCUS_COUNT + 1))
            cat "$LOCUS_FASTA" >> "$TEMP_FASTA"
        else
            echo "SKIP $LOCUS_NAME: missing $MISSING_COUNT individual(s): ${MISSING_LIST[*]}" >&2
        fi

        rm -f "$LOCUS_FASTA"
        unset PRESENT_INDIVIDUALS
    done

    [[ $TOTAL_LOCUS_COUNT -gt 0 ]] || die "No .fa, .fas, or .fasta files were found in '$FAS_DIR'"
    [[ $VALID_LOCUS_COUNT -gt 0 ]] || die "No FASTA locus contained every individual listed in the IMAP file"

    for individual in "${INDIVIDUAL_LIST[@]}"; do
        echo ">$individual" >> "$CONCAT_FASTA"
        awk -v wanted="$individual" '
            /^>/ { capture = (substr($0, 2) == wanted); next }
            capture { printf "%s", $0; capture = 0 }
            END { print "" }
        ' "$TEMP_FASTA" >> "$CONCAT_FASTA"
    done

    echo "  Number of loci : $VALID_LOCUS_COUNT"

    snp-sites -v -o "$VCF_FILE_TEMP" "$CONCAT_FASTA" || die "snp-sites failed to generate a VCF file"
    [[ -s "$VCF_FILE_TEMP" ]] || die "snp-sites generated an empty VCF file"
    convert_haploid_to_diploid "$VCF_FILE_TEMP" "$GENERATED_VCF" || die "Failed to convert haploid genotypes to diploid genotypes"
    [[ -s "$GENERATED_VCF" ]] || die "Diploid VCF conversion generated an empty file"
    VCF_FILE="$GENERATED_VCF"
fi

# Process each tree in the treelist file.
TREE_COUNT=0
PROCESSED_TREES=0

while IFS= read -r tree || [[ -n "$tree" ]]; do
    if [[ -z "$tree" || "$tree" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    TREE_COUNT=$((TREE_COUNT + 1))
    TREE_FILE="$PREFIX-Tree${TREE_COUNT}.tree"
    CURRENT_PREFIX="${PREFIX}-Tree${TREE_COUNT}"
    
    echo "=================================================================="
    echo "Processing tree $TREE_COUNT..."
    
    if if_tree=$(printf '%s\n' "$tree" | nw_display - 2>/dev/null) && [[ -n "$(printf '%s' "$if_tree" | tr -d '[:space:]')" ]]; then
    	echo "Tree topology: $tree"
		printf '%s\n' "$tree" | tr -d '[:space:]' > "$TREE_FILE"
    else
        die "Invalid Newick tree on non-comment line $TREE_COUNT of '$TREELIST_FILE'"
    fi
        
    # run Dsuite Dtrios
    echo "Running 'Dsuite Dtrios' for tree $TREE_COUNT..."
    DSUITE_LOG="${CURRENT_PREFIX}.Dsuite.log"
    Dsuite Dtrios "$VCF_FILE" "$IMAP_FILE" -t "$TREE_FILE" -o "$CURRENT_PREFIX" > "$DSUITE_LOG" 2>&1 || \
        die "Dsuite Dtrios failed for tree $TREE_COUNT; see '$DSUITE_LOG'"
    
    # check output_file
    D_FILE="${CURRENT_PREFIX}_tree.txt"
    if [[ ! -f "$D_FILE" ]]; then
        die "Dsuite output file was not found: '$D_FILE'"
    fi
    
    # process D file
    OUTPUT_FILE="${CURRENT_PREFIX}.sig-triples"
    TEMP_FILE=$(mktemp "${PREFIX_DIR}/.dbpp-filtered.XXXXXX.tsv") || die "Could not create a temporary results file"
    
    echo "Calculating Dp and filtering results (${FILTER_COL} <= $CUTOFF)..."
    
    # calculate Dp-value and filter non-sig triples
    awk -v filter_col="$FILTER_COL" -v cutoff="$CUTOFF" -v N_TRIPLES="$N_TRIPLES" '
    BEGIN {
        OFS = "\t"
        p1_idx = 1; p2_idx = 2; p3_idx = 3; dstat_idx = 4; zscore_idx = 5; pval_idx = 6
        f4_ratio_idx = 7; BBAA_idx = 8; ABBA_idx = 9; BABA_idx = 10
    }
    NR == 1 {
        header = $0
        for (i=1; i<=NF; i++) {
            if ($i == "P1") p1_idx = i
            if ($i == "P2") p2_idx = i
            if ($i == "P3") p3_idx = i
            if ($i == "Dstatistic") dstat_idx = i
            if ($i == "Z-score") zscore_idx = i
            if ($i == "p-value") pval_idx = i
            if ($i == "f4-ratio") f4_ratio_idx = i
            if ($i == "BBAA") BBAA_idx = i
            if ($i == "ABBA") ABBA_idx = i
            if ($i == "BABA") BABA_idx = i
        }
        print header, "Dp", "adjusted_p_value"
        next
    }
    {
        BBAA = $BBAA_idx
        ABBA = $ABBA_idx
        BABA = $BABA_idx
        total = BBAA + ABBA + BABA
        Dp = (total > 0) ? (ABBA - BABA) / total : 0
        
        if (filter_col == "Z-score") {
            zscore = $zscore_idx
            if (zscore >= cutoff) {
                print $0, Dp
            }
        } else if (filter_col == "p-value") {
            adjusted_p = $pval_idx * N_TRIPLES
            if (adjusted_p > 1) adjusted_p = 1
            if (adjusted_p <= cutoff) {
                print $0, Dp, adjusted_p
            }
        }
    }' "$D_FILE" > "$TEMP_FILE"
    
    if [[ $(wc -l < "$TEMP_FILE") -le 1 ]]; then
        echo "No results passed the filter for tree $TREE_COUNT"
        head -n 1 "$TEMP_FILE" > "$OUTPUT_FILE"
        rm -f "$TEMP_FILE"
        rm -f "${CURRENT_PREFIX}_BBAA"* "${CURRENT_PREFIX}_combine"* "${CURRENT_PREFIX}_Dmin"* "$D_FILE"
        continue
    fi
    
    head -n1 "$TEMP_FILE" > "$OUTPUT_FILE"
    tail -n+2 "$TEMP_FILE" | sort -t$'\t' -k11,11nr >> "$OUTPUT_FILE"
    
    rm -f "$TEMP_FILE"
    rm -f "${CURRENT_PREFIX}_BBAA"*
    rm -f "${CURRENT_PREFIX}_combine"*
    rm -f "${CURRENT_PREFIX}_Dmin"*
    rm -f "${CURRENT_PREFIX}_tree.txt"
    
    RESULT_COUNT=$(tail -n+2 "$OUTPUT_FILE" | wc -l)
    echo "Filtered results for tree $TREE_COUNT: $RESULT_COUNT trios passed the filter"
    echo "Results saved to: $OUTPUT_FILE"
    
    PROCESSED_TREES=$((PROCESSED_TREES + 1))
    
done < "$TREELIST_FILE"

[[ $TREE_COUNT -gt 0 ]] || die "Tree list contains no Newick trees"

echo "=================================================================="
echo "Processing completed: $PROCESSED_TREES of $TREE_COUNT candidate tree(s) produced significant triples."

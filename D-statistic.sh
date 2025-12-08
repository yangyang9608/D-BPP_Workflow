#!/bin/bash
usage() {
    echo "Usage: $0 --vcf <vcf_file> --imap <imap_file> --treelist <treelist_file> [--prefix <output_prefix>] [--filter Z-score|p-value] [--cutoff <value>]"
    echo ""
    echo "Required parameters:"
    echo "  --vcf <file>          Input VCF file"
    echo "  --imap <file>         Individual to species mapping file"
    echo "  --treelist <file>     File containing multiple trees (one per line)"
    echo ""
    echo "Optional parameters:"
    echo "  --filter <col>        Filter criteria: 'Z-score' or 'p-value' (default: p-value)"
    echo "  --cutoff <value>      Cutoff value for filtering (default: 0.01)"
    echo "  --prefix <prefix>     Output prefix (path will be created if needed; default: Sig-Dp)"
	echo ""
	echo "Output:"
	echo "  For each tree in treelist, generates prefix-Tree*-triples.txt containing"
	echo "  all significant triples sorted by Dp value in descending order"
    exit 1
}

# default values
FILTER_COL="p-value"
FILTER_COL_DEFAULT=1
CUTOFF="0.01"
CUTOFF_DEFAULT=1
PREFIX="D-sig"

if [[ $# -eq 0 ]]; then
    usage
fi

#########
while [[ $# -gt 0 ]]; do
    case $1 in
        --vcf)
            VCF_FILE="$2"
            shift 2
            ;;
        --imap)
            IMAP_FILE="$2"
            shift 2
            ;;
        --treelist)
            TREELIST_FILE="$2"
            shift 2
            ;;
        --filter)
            FILTER_COL="$2"
			FILTER_COL_DEFAULT=0
            shift 2
            ;;
        --cutoff)
            CUTOFF="$2"
			CUTOFF_DEFAULT=0
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done


#check Required parameters and files
if [[ -z "$VCF_FILE" || -z "$IMAP_FILE" || -z "$TREELIST_FILE" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

for file in "$VCF_FILE" "$IMAP_FILE" "$TREELIST_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Input file $file does not exist!"
        exit 1
    fi
done

sum=$(( CUTOFF_DEFAULT + FILTER_COL_DEFAULT ))
if [[ $sum -eq 1 ]]; then
    echo "Error: The --cutoff and --filter parameters must be provided simultaneously"
	exit 1
fi

# check filter
if [[ "$FILTER_COL" != "Z-score" && "$FILTER_COL" != "p-value" ]]; then
    echo "Error: filter_col must be either 'Z-score' or 'p-value'"
    echo "Current value: $FILTER_COL"
    exit 1
fi


# check cutoff
if ! [[ "$CUTOFF" =~ ^-?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]; then
    echo "Error: cutoff must be a valid number"
    echo "Current value: $CUTOFF"
    exit 1
fi

#Create the output directory if it does not exist
PREFIX_DIR=$(dirname "$PREFIX")
if [[ "$PREFIX_DIR" != "." && ! -d "$PREFIX_DIR" ]]; then
    echo "Creating directory: $PREFIX_DIR"
    mkdir -p "$PREFIX_DIR"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create directory $PREFIX_DIR"
        exit 1
    fi
fi

echo "Starting analysis with parameters:"
echo "  VCF file: $VCF_FILE"
echo "  IMAP file: $IMAP_FILE" 
echo "  Tree list: $TREELIST_FILE"
echo "  Output prefix: $PREFIX"
echo "  Filter criteria: $FILTER_COL"
echo "  Cutoff value: $CUTOFF"
echo ""

# Process each tree in the treelist file.
TREE_COUNT=0
PROCESSED_TREES=0

while IFS= read -r tree || [[ -n "$tree" ]]; do
    if [[ -z "$tree" || "$tree" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    TREE_COUNT=$((TREE_COUNT + 1))
    TREE_FILE="$PREFIX_DIR/Tree${TREE_COUNT}.txt"
    CURRENT_PREFIX="${PREFIX}-Tree${TREE_COUNT}"
    
    echo "=================================================================="
    echo "Processing tree $TREE_COUNT..."
    echo "Tree topology: $tree"
    
    echo "$tree" > "$TREE_FILE"
    
    # run Dsuite Dtrios
    echo "Running Dsuite Dtrios for tree $TREE_COUNT..."
    Dsuite Dtrios "$VCF_FILE" "$IMAP_FILE" --tree="$TREE_FILE" -o "$CURRENT_PREFIX"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Dsuite Dtrios failed for tree $TREE_COUNT"
        rm -f "$TREE_FILE"
        exit 1
    fi
    
    # check output_file
    D_FILE="${CURRENT_PREFIX}_tree.txt"
    if [[ ! -f "$D_FILE" ]]; then
        echo "Error: D output file not found: $D_FILE"
        rm -f "$TREE_FILE"
        exit 1
    fi
    
    # process D file
    OUTPUT_FILE="${CURRENT_PREFIX}-triples.txt"
	TEMP_FILE="temp_filtered_${RANDOM}.txt"
    
    echo "Calculating Dp and filtering results (${FILTER_COL} $(if [[ "$FILTER_COL" == "Z-score" ]]; then echo ">="; else echo "<="; fi) $CUTOFF)..."
    
    # calculate Dp-value and filter non-sig triples
    awk -v filter_col="$FILTER_COL" -v cutoff="$CUTOFF" '
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
        print header, "Dp"
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
            pval = $pval_idx
            if (pval <= cutoff) {
                print $0, Dp
            }
        }
    }' "$D_FILE" > "$TEMP_FILE"
    
    if [[ $(wc -l < "$TEMP_FILE") -le 1 ]]; then
        echo "No results passed the filter for tree $TREE_COUNT"
        rm -f "$TEMP_FILE" "$TREE_FILE"
        continue
    fi
    
    head -n1 "$TEMP_FILE" > "$OUTPUT_FILE"
    tail -n+2 "$TEMP_FILE" | sort -t$'\t' -k11,11nr >> "$OUTPUT_FILE"
    
	rm -f "$TEMP_FILE"
    
    RESULT_COUNT=$(tail -n+2 "$OUTPUT_FILE" | wc -l)
    echo "Filtered results for tree $TREE_COUNT: $RESULT_COUNT trios passed the filter"
    echo "Results saved to: $OUTPUT_FILE"
    
    PROCESSED_TREES=$((PROCESSED_TREES + 1))
    
done < "$TREELIST_FILE"

echo "=================================================================="
echo "Processing completed!"

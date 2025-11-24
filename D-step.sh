#!/bin/bash
usage() {
    echo "Usage: bash $0 (--fasta_dir <fasta_dir> |--vcf_file <vcf_file>) --imap <imap_file> --treelist <treelist_file> [--prefix <output_prefix>] [--cutoff <value>]"
    echo ""
	echo "Required parameters (choose one input type):"
	echo "  --fasta_dir <dir>     Directory containing locus FASTA files"
	echo "  --vcf_file <file>     VCF file"

    echo "Other Required parameters:"
    echo "  --imap <file>         Individual to species mapping file"
    echo "  --treelist <file>     File containing multiple trees (one per line)"
    echo ""
    echo "Optional parameters:"
    echo "  --cutoff <value>      Cutoff value for p-value (default: 0.01)"
    echo "  --prefix <prefix>     Output prefix (path will be created if needed; default: Sig-Dp)"
	echo ""
	echo "Output:"
	echo "  For each tree in treelist, generates prefix-Tree*-triples.txt containing"
	echo "  all significant triples (after Bonferroni correction) sorted by Dp value in descending order"
    exit 1
}

# default values
FILTER_COL="p-value"
CUTOFF="0.01"
PREFIX="D-sig"

if [[ $# -eq 0 ]]; then
    usage
fi

#########
while [[ $# -gt 0 ]]; do
    case $1 in
        --fasta_dir)
            FAS_DIR="$2"
            shift 2
            ;;
        --vcf_file)
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
        --cutoff)
            CUTOFF="$2"
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
if [[ -z "$IMAP_FILE" || -z "$TREELIST_FILE" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

if [[ -n "$FAS_DIR" && -n "$VCF_FILE" ]]; then
    echo "Error: Cannot specify both --fasta_dir and --phylip_file"
    usage
elif [[ -z "$FAS_DIR" && -z "$VCF_FILE" ]]; then
    echo "Error: Must specify either --fasta_dir or --phylip_file"
    usage
elif [[ -n "$FAS_DIR" && ! -d "$FAS_DIR" ]]; then
    echo "Error: FASTA directory $FAS_DIR does not exist!"
    exit 1
elif [[ -n "$VCF_FILE" && ! -f "$VCF_FILE" ]]; then
    echo "Error: VCF file $VCF_FILE does not exist!"
    exit 1
fi

for file in "$IMAP_FILE" "$TREELIST_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Input file $file does not exist!"
        exit 1
    fi
done

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


declare -A INDIVIDUALS
declare -A SPECIES
INDIVIDUAL_LIST=()
while IFS=$'\t' read -r individual species || [[ -n "$individual" ]]; do
    INDIVIDUALS["$individual"]=1
    INDIVIDUAL_LIST+=("$individual")

	if [[ "$species" != "Outgroup" ]]; then
        SPECIES["$species"]=1
    fi
done < "$IMAP_FILE"
TOTAL_INDIVIDUALS=${#INDIVIDUAL_LIST[@]}
N_SPECIES=${#SPECIES[@]}
N_TRIPLES=$(( N_SPECIES * (N_SPECIES - 1) * (N_SPECIES - 2) / 6 ))


NEW_CUTOFF=$(echo "$CUTOFF / $N_TRIPLES" | bc -l)
echo "Starting analysis with parameters:"
echo "  Fasta files: $FAS_DIR"
echo "  IMAP file: $IMAP_FILE" 
echo "  Tree list: $TREELIST_FILE"
echo "  Output prefix: $PREFIX"
echo "  Filter criteria: $FILTER_COL"
echo "  Cutoff value: $CUTOFF ($(printf "%.4f" "$NEW_CUTOFF") after Bonferroni Correction)"

#Concatenate multi-locus FASTA

if [[ -n "$FASTA_DIR" ]]; then
	echo "FASTA directory: $FASTA_DIR"
	CONCAT_FASTA="${PREFIX}_concatenated.fasta"
	TEMP_FASTA="${PREFIX}_temp.fasta"
	
	> "$CONCAT_FASTA"
	> "$TEMP_FASTA"
	
	VALID_LOCUS_COUNT=0
	TOTAL_LOCUS_COUNT=0
	
	for fasta_file in "$FAS_DIR"/*.fasta "$FAS_DIR"/*.fa "$FAS_DIR"/*.fas; do
		if [[ ! -f "$fasta_file" ]]; then
	        continue 
	    fi
	
	    TOTAL_LOCUS_COUNT=$((TOTAL_LOCUS_COUNT + 1))
	    LOCUS_NAME=$(basename "$fasta_file")
	    
	    declare -A PRESENT_INDIVIDUALS
	    MISSING_COUNT=0
	    
	    while IFS= read -r line || [[ -n "$line" ]]; do
	        if [[ "$line" =~ ^\> ]]; then
	            seq_name="${line:1}"
	            seq_name=$(echo "$seq_name" | awk '{print $1}')
	            PRESENT_INDIVIDUALS["$seq_name"]=1
	        fi
	    done < "$fasta_file"
	    
	    MISSING_LIST=()
	    for individual in "${INDIVIDUAL_LIST[@]}"; do
	        if [[ -z "${PRESENT_INDIVIDUALS[$individual]}" ]]; then
	            MISSING_COUNT=$((MISSING_COUNT + 1))
	            MISSING_LIST+=("$individual")
	        fi
	    done
	    
	    if [[ $MISSING_COUNT -eq 0 ]]; then
	        VALID_LOCUS_COUNT=$((VALID_LOCUS_COUNT + 1))
	        cat "$fasta_file" >> "$TEMP_FASTA"
	    else
	        echo "    ✗ SKIP - Missing $MISSING_COUNT individuals: ${MISSING_LIST[*]}"
	        echo "Locus: $LOCUS_NAME - Missing $MISSING_COUNT individuals: ${MISSING_LIST[*]}"
	    fi
	    
	    unset PRESENT_INDIVIDUALS
	done

	for individual in "${INDIVIDUAL_LIST[@]}"; do
    	echo ">$individual" >> "$CONCAT_FASTA"
    
	    grep -A 1 "^>$individual" "$TEMP_FASTA" | grep -v "^\-\-" | grep -v "^>$individual" | tr -d '\n' >> "$CONCAT_FASTA"
    	echo "" >> "$CONCAT_FASTA"
	done

	rm -f "$TEMP_FASTA"
	echo "Number of loci : $VALID_LOCUS_COUNT"


	VCF_FILE="${PREFIX}_snps.vcf"
	snp-sites -v -o "$VCF_FILE" "$CONCAT_FASTA"

	if [[ $? -ne 0 ]] || [[ ! -f "$VCF_FILE" ]]; then
    	echo "Error: snp-sites failed to generate VCF file!"
    	exit 1
	fi

	rm -f "$CONCAT_FASTA"
fi

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
    echo "Running 'Dsuite Dtrios' for tree $TREE_COUNT..."
    Dsuite Dtrios "$VCF_FILE" "$IMAP_FILE" --tree="$TREE_FILE" -o "$CURRENT_PREFIX" > /dev/null 2>&1
    
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
    
    echo "Calculating Dp and filtering results (${FILTER_COL} <= ($(printf "%.4f" "$NEW_CUTOFF"))..."
    
    # calculate Dp-value and filter non-sig triples
    awk -v filter_col="$FILTER_COL" -v cutoff="$NEW_CUTOFF" '
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

if [[ -n "$FASTA_DIR" ]]; then
	rm "$VCF_FILE"
fi

echo "=================================================================="
echo "Processing completed!"

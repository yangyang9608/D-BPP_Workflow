#!/bin/bash

usage() {
    echo "Usage: bash $0 (--fasta_dir <fasta_directory> | --phylip_file <phylip_file>) --imap <imap_file> --tree <tree_file> --dstat <dstat_file> --prefix <output_prefix>"
    echo ""
	echo "Required parameters (choose one input type):"
    echo "  --fasta_dir <dir>     Directory containing locus FASTA files"
    echo "  --phylip_file <file>  Existing BPP-PHYLIP file"
    echo ""
    echo "Other required parameters:"
    echo "  --imap <file>         Individual to species mapping file (tab-delimited)"
    echo "  --tree <file>         Species tree file"
    echo "  --dstat <file>        D-statistic results file"
    echo "  --prefix <prefix>     Output prefix for BPP files"
    echo ""
	echo "Optional parameters:"
    echo "  --skip_validation     Skip PHYLIP file format validation (only with --phylip_file)"
    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

SKIP_VALIDATION=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --fasta_dir)
            FASTA_DIR="$2"
            shift 2
            ;;
        --phylip_file)
            PHYLIP_FILE="$2"
            shift 2
            ;;
        --imap)
            IMAP_FILE="$2"
            shift 2
            ;;
        --tree)
            TREE_FILE="$2"
            shift 2
            ;;
        --dstat)
            DSTAT_FILE="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
		--skip_validation)
            SKIP_VALIDATION=true
            shift
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

####################
if [[ -n "$FASTA_DIR" && -n "$PHYLIP_FILE" ]]; then
    echo "Error: Cannot specify both --fasta_dir and --phylip_file"
    usage
elif [[ -z "$FASTA_DIR" && -z "$PHYLIP_FILE" ]]; then
    echo "Error: Must specify either --fasta_dir or --phylip_file"
    usage
elif [[ -n "$FASTA_DIR" && ! -d "$FASTA_DIR" ]]; then
    echo "Error: FASTA directory $FASTA_DIR does not exist!"
    exit 1
elif [[ -n "$PHYLIP_FILE" && ! -f "$PHYLIP_FILE" ]]; then
    echo "Error: PHYLIP file $PHYLIP_FILE does not exist!"
    exit 1
fi

if [[ "$SKIP_VALIDATION" == true && -z "$PHYLIP_FILE" ]]; then
    echo "Error: --skip_validation can only be used with --phylip_file"
    usage
fi
####################
if [[ -z "$IMAP_FILE" || -z "$TREE_FILE" || -z "$DSTAT_FILE" || -z "$PREFIX" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

for file in "$IMAP_FILE" "$TREE_FILE" "$DSTAT_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Input file $file does not exist!"
        exit 1
    fi
done

PREFIX_DIR=$(dirname "$PREFIX")
if [[ ! -d "$PREFIX_DIR" ]]; then
    echo "Creating directory: $PREFIX_DIR"
    mkdir -p "$PREFIX_DIR"
fi

echo "Starting BPP input file generation..."
echo "====================================="

# read imap file
echo "Step 1: Reading IMAP file and identifying outgroup..."
declare -A INDIV_TO_SPECIES
declare -A SPECIES_INDIVS
OUTGROUP_INDS=()
IMAP_BPP="${PREFIX}.imap"

> "$IMAP_BPP"

while IFS=$'\t' read -r individual species || [[ -n "$individual" ]]; do
    if [[ -z "$individual" || "$individual" =~ ^# ]]; then
        continue
    fi
    
    individual=$(echo "$individual" | xargs)
    species=$(echo "$species" | xargs)
    
    INDIV_TO_SPECIES["$individual"]="$species"
    
    if [[ "$species" == "Outgroup" ]]; then
        OUTGROUP_INDS+=("$individual")
    else
		{
			echo -e "${individual}\t${species}" >> "$IMAP_BPP"
		} >> "$IMAP_BPP"
        if [[ -z "${SPECIES_INDIVS[$species]}" ]]; then
            SPECIES_INDIVS["$species"]="$individual"
        else
            SPECIES_INDIVS["$species"]="${SPECIES_INDIVS[$species]} $individual"
        fi
    fi
done < "$IMAP_FILE"

echo "Outgroup individuals: ${#OUTGROUP_INDS[@]}"
echo "Ingroup species: ${!SPECIES_INDIVS[@]}"
echo "BPP imap file: ${PREFIX}.imap"

#red tree topology
echo ""
echo "Step 2: Reading tree file..."
if [[ -f "$TREE_FILE" ]]; then
    TREE_CONTENT=$(cat "$TREE_FILE")
    echo "Tree topology: $TREE_CONTENT"
fi

# Read D-statistic results and prepare for f-branch analysis
echo ""
echo "Step 3: Reading D-statistic results..."
declare -a TRIPLES_ARRAY
declare -A TRIPLES_RANK  # Store rank of each triple (line number)

if [[ -f "$DSTAT_FILE" ]]; then
    # Read header
    IFS= read -r header_line < "$DSTAT_FILE"
    
    # Read triples data (skip header)
    line_number=1
    while IFS= read -r line; do
        ((line_number++))
        
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Extract first three columns (P1, P2, P3)
        p1=$(echo "$line" | awk '{print $1}')
        p2=$(echo "$line" | awk '{print $2}')
        p3=$(echo "$line" | awk '{print $3}')
        
        # Create triple identifier and store data
        triple_id="${p1},${p2},${p3}"
        TRIPLES_ARRAY+=("$triple_id")
        TRIPLES_RANK["$triple_id"]=$((line_number - 1))  # Rank starts from 1
        
    done < <(tail -n +2 "$DSTAT_FILE")  # Skip header

	# Get anchor triple (highest ranked - first data line)
    if [[ ${#TRIPLES_ARRAY[@]} -gt 0 ]]; then
        ANCHOR_TRIPLE="${TRIPLES_ARRAY[0]}"
        ANCHOR_P1=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f1)
        ANCHOR_P2=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f2)
        ANCHOR_P3=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f3)
        echo "    Anchor triple: $ANCHOR_TRIPLE (P1=$ANCHOR_P1, P2=$ANCHOR_P2, P3=$ANCHOR_P3)"
    else
        echo "  Warnings: No triples found in D-statistic file"
        exit 1
    fi
fi

# Function to check if a set of taxa is monophyletic
check_monophyly() {
    local taxa=("$@")
    local taxon_list
    taxon_list=$(IFS=' '; echo "${taxa[*]}")
    
    # Extract the clade containing these taxa and check if output is non-empty
    local clade_output
    clade_output=$(nw_clade -m "$TREE_FILE" $taxon_list 2>/dev/null)
	#echo "$TREE_FILE###$clade_output" >&2
    
    if [[ -n "$(echo "$clade_output" | tr -d '[:space:]')" ]]; then
        return 0 
    else
		#echo "###$taxon_list"  >&2
        return 1 
    fi
}

# Function to generate all possible good subsets
generate_good_subsets() {
    local anchor_taxon="$1"
    local diff_set=("${@:2}")  # Remaining arguments are the difference set
    
    local good_subsets=()
    
    # Generate all non-empty subsets that contain the anchor taxon
    local n=${#diff_set[@]}
    
    # Use bitmask to generate all subsets
    for ((mask = 1; mask < (1 << n); mask++)); do
        local subset=()
        local contains_anchor=false
        
        for ((i = 0; i < n; i++)); do
            if (((mask >> i) & 1)); then
                local taxon="${diff_set[i]}"
                subset+=("$taxon")
                if [[ "$taxon" == "$anchor_taxon" ]]; then
                    contains_anchor=true
                fi
            fi
        done
		#echo "###${subset[*]}" >&2
        
        # Check if subset contains anchor and has at least 2 taxa
        if [[ "$contains_anchor" == true && ${#subset[@]} -ge 2 ]]; then
            # Check monophyly
            if check_monophyly "${subset[@]}"; then
                # Store subset as sorted string for consistency
                local sorted_subset
                sorted_subset=$(printf "%s\n" "${subset[@]}" | sort | tr '\n' ',' | sed 's/,$//')
                good_subsets+=("$sorted_subset")
            fi
        fi
    done
    
    # Return unique good subsets
    printf "%s\n" "${good_subsets[@]}" | sort -u
}

# Build difference sets
declare -a DIFF_P3=("$ANCHOR_P3")
declare -a DIFF_P2=("$ANCHOR_P2")
declare -a DIFF_P1=("$ANCHOR_P1")

for triple in "${TRIPLES_ARRAY[@]:1}"; do
    p1=$(echo "$triple" | cut -d',' -f1)
    p2=$(echo "$triple" | cut -d',' -f2)
    p3=$(echo "$triple" | cut -d',' -f3)
    
    # Check for shared pairs and add to difference sets
    if [[ "$p1" == "$ANCHOR_P1" && "$p2" == "$ANCHOR_P2" ]]; then
        DIFF_P3+=("$p3")
    fi
    if [[ "$p1" == "$ANCHOR_P1" && "$p3" == "$ANCHOR_P3" ]]; then
        DIFF_P2+=("$p2")
    fi
    if [[ "$p2" == "$ANCHOR_P2" && "$p3" == "$ANCHOR_P3" ]]; then
        DIFF_P1+=("$p1")
    fi
done
#echo ""
#echo "  Difference set P3 (${#DIFF_P3[@]} taxa): ${DIFF_P3[*]}"
#echo "  Difference set P2 (${#DIFF_P2[@]} taxa): ${DIFF_P2[*]}"
#echo "  Difference set P1 (${#DIFF_P1[@]} taxa): ${DIFF_P1[*]}"

GOOD_P1_SUBSETS=($(generate_good_subsets "$ANCHOR_P1" "${DIFF_P1[@]}"))
GOOD_P2_SUBSETS=($(generate_good_subsets "$ANCHOR_P2" "${DIFF_P2[@]}"))
GOOD_P3_SUBSETS=($(generate_good_subsets "$ANCHOR_P3" "${DIFF_P3[@]}"))
#echo ""
#echo "  Good P1 subsets: ${#GOOD_P1_SUBSETS[@]}"
#echo "  Good P2 subsets: ${#GOOD_P2_SUBSETS[@]}"
#echo "  Good P3 subsets: ${#GOOD_P3_SUBSETS[@]}"


#Generate all candidate combinations for f-branch

# Function to convert subset string to array
subset_to_array() {
    local subset_str="$1"
    IFS=',' read -r -a array <<< "$subset_str"
    printf "%s\n" "${array[@]}"
}

# Function to generate all triples from a candidate combination
generate_triples_from_candidate() {
    local p1_subset_str="$1"
    local p2_subset_str="$2" 
    local p3_subset_str="$3"
    
    local p1_array=($(subset_to_array "$p1_subset_str"))
    local p2_array=($(subset_to_array "$p2_subset_str"))
    local p3_array=($(subset_to_array "$p3_subset_str"))
    
    local triples=()
    
    for p1 in "${p1_array[@]}"; do
        for p2 in "${p2_array[@]}"; do
            for p3 in "${p3_array[@]}"; do
                triples+=("${p1},${p2},${p3}")
				#echo "${p1},${p2},${p3}" >&2
            done
        done
    done
    
    printf "%s\n" "${triples[@]}"
}

# Function to score a candidate combination
score_candidate() {
    local p1_subset="$1"
    local p2_subset="$2"
    local p3_subset="$3"
    
    # Generate all possible triples from this candidate
    local all_triples
    all_triples=($(generate_triples_from_candidate "$p1_subset" "$p2_subset" "$p3_subset"))
    
    # Check which triples exist in our dataset
    local existing_triples=()
    local total_rank=0
    local missing_count=0
    
    for triple in "${all_triples[@]}"; do
        if [[ -n "${TRIPLES_RANK[$triple]}" ]]; then
            existing_triples+=("$triple")
            total_rank=$((total_rank + TRIPLES_RANK["$triple"]))
        else
            missing_count=$((missing_count + 1))
        fi
    done
    
    # If any triple is missing, candidate is invalid
    if [[ $missing_count -gt 0 ]]; then
        echo "0,0,invalid"  # triples_count, rank_sum, status
        return
    fi
    
    local triples_count=${#existing_triples[@]}
    echo "${triples_count},${total_rank},valid"
}

# Generate and evaluate all candidate combinations
declare -a CANDIDATE_RESULTS

# Type 1: Single dimension candidates
for p1_subset in "${GOOD_P1_SUBSETS[@]}"; do
    score_result=$(score_candidate "$p1_subset" "$ANCHOR_P2" "$ANCHOR_P3")
    IFS=',' read -r triples_count rank_sum status <<< "$score_result"
    if [[ "$status" == "valid" ]]; then
        CANDIDATE_RESULTS+=("SINGLE_P1:${p1_subset}:${ANCHOR_P2}:${ANCHOR_P3}:${triples_count}:${rank_sum}")
    fi
done

for p2_subset in "${GOOD_P2_SUBSETS[@]}"; do
    score_result=$(score_candidate "$ANCHOR_P1" "$p2_subset" "$ANCHOR_P3")
    IFS=',' read -r triples_count rank_sum status <<< "$score_result"
    if [[ "$status" == "valid" ]]; then
        CANDIDATE_RESULTS+=("SINGLE_P2:${ANCHOR_P1}:${p2_subset}:${ANCHOR_P3}:${triples_count}:${rank_sum}")
    fi
done

for p3_subset in "${GOOD_P3_SUBSETS[@]}"; do
    score_result=$(score_candidate "$ANCHOR_P1" "$ANCHOR_P2" "$p3_subset")
    IFS=',' read -r triples_count rank_sum status <<< "$score_result"
    if [[ "$status" == "valid" ]]; then
        CANDIDATE_RESULTS+=("SINGLE_P3:${ANCHOR_P1}:${ANCHOR_P2}:${p3_subset}:${triples_count}:${rank_sum}")
    fi
done

# Type 2: Double dimension candidates
for p1_subset in "${GOOD_P1_SUBSETS[@]}"; do
    for p2_subset in "${GOOD_P2_SUBSETS[@]}"; do
        score_result=$(score_candidate "$p1_subset" "$p2_subset" "$ANCHOR_P3")
        IFS=',' read -r triples_count rank_sum status <<< "$score_result"
        if [[ "$status" == "valid" ]]; then
            CANDIDATE_RESULTS+=("DOUBLE_P1P2:${p1_subset}:${p2_subset}:${ANCHOR_P3}:${triples_count}:${rank_sum}")
        fi
    done
done

for p1_subset in "${GOOD_P1_SUBSETS[@]}"; do
    for p3_subset in "${GOOD_P3_SUBSETS[@]}"; do
        score_result=$(score_candidate "$p1_subset" "$ANCHOR_P2" "$p3_subset")
        IFS=',' read -r triples_count rank_sum status <<< "$score_result"
        if [[ "$status" == "valid" ]]; then
            CANDIDATE_RESULTS+=("DOUBLE_P1P3:${p1_subset}:${ANCHOR_P2}:${p3_subset}:${triples_count}:${rank_sum}")
        fi
    done
done

for p2_subset in "${GOOD_P2_SUBSETS[@]}"; do
    for p3_subset in "${GOOD_P3_SUBSETS[@]}"; do
        score_result=$(score_candidate "$ANCHOR_P1" "$p2_subset" "$p3_subset")
        IFS=',' read -r triples_count rank_sum status <<< "$score_result"
        if [[ "$status" == "valid" ]]; then
            CANDIDATE_RESULTS+=("DOUBLE_P2P3:${ANCHOR_P1}:${p2_subset}:${p3_subset}:${triples_count}:${rank_sum}")
        fi
    done
done

# Type 3: Triple dimension candidates
for p1_subset in "${GOOD_P1_SUBSETS[@]}"; do
    for p2_subset in "${GOOD_P2_SUBSETS[@]}"; do
        for p3_subset in "${GOOD_P3_SUBSETS[@]}"; do
            score_result=$(score_candidate "$p1_subset" "$p2_subset" "$p3_subset")
            IFS=',' read -r triples_count rank_sum status <<< "$score_result"
            if [[ "$status" == "valid" ]]; then
                CANDIDATE_RESULTS+=("TRIO_P1P2P3:${p1_subset}:${p2_subset}:${p3_subset}:${triples_count}:${rank_sum}")
            fi
        done
    done
done

#echo ""
#echo "  Total valid candidates found: ${#CANDIDATE_RESULTS[@]}"

# Select optimal candidate
if [[ ${#CANDIDATE_RESULTS[@]} -eq 0 ]]; then
    # Create default candidate using just the anchor triple
    ANCHOR_TRIPLE_ID="${ANCHOR_P1}-${ANCHOR_P2}-${ANCHOR_P3}"
    ANCHOR_RANK="${TRIPLES_RANK[$ANCHOR_TRIPLE_ID]}"
    
    # Create single-element subsets for the anchor triple
    P1_SUBSET="$ANCHOR_P1"
    P2_SUBSET="$ANCHOR_P2" 
    P3_SUBSET="$ANCHOR_P3"
   
    CANDIDATE_RESULTS+=("SINGLE_ANCHOR:${P1_SUBSET}:${P2_SUBSET}:${P3_SUBSET}:1:${ANCHOR_RANK}")
fi

# Sort candidates by triples_count (descending) and then by rank_sum (ascending)
declare -a SORTED_CANDIDATES
for candidate in "${CANDIDATE_RESULTS[@]}"; do
	#echo "$candidate"
    IFS=':' read -r type p1_subset p2_subset p3_subset triples_count rank_sum <<< "$candidate"
    # Use negative rank_sum for proper sorting (we want lower rank_sum to be better)
    SORTED_CANDIDATES+=("$(printf "%05d-%05d:%s" "$((10000 - triples_count))" "$rank_sum" "$candidate")")
done

# Sort and extract the best candidate
BEST_CANDIDATE_ENC=$(printf "%s\n" "${SORTED_CANDIDATES[@]}" | sort | head -n1 | cut -d':' -f2-)
IFS=':' read -r best_type best_p1 best_p2 best_p3 best_triples_count best_rank_sum <<< "$BEST_CANDIDATE_ENC"

#echo "  Optimal candidate selected:"
#echo "    Type: $best_type"
if [[ "$best_p1" == *","* ]]; then
	echo "    P1 branch: LCA($best_p1)"
else
	echo "    P1 branch: $best_p1"
fi
if [[ "$best_p2" == *","* ]]; then
	echo "    P2 branch: LCA($best_p2)"
else
	echo "    P2 branch: $best_p2"
fi
if [[ "$best_p3" == *","* ]]; then
	echo "    P3 branch: LCA($best_p3)"
else
	echo "    P3 branch: $best_p3"
fi
echo "    Triples explained: $best_triples_count"


#############################################
# generating Phylip file
#: <<'NOTE'
echo ""
echo "Step 4: Processing or checking BPP PHYLIP file..."

SEQ_FILE="${PREFIX}_bpp.phy"
LOCUS_COUNT=0

if [[ -n "$FASTA_DIR" ]]; then
    echo "FASTA directory: $FASTA_DIR"
    
	> "$SEQ_FILE"
	
	for fasta_file in "$FASTA_DIR"/*.fasta "$FASTA_DIR"/*.fa "$FASTA_DIR"/*.fas; do
	    if [[ ! -f "$fasta_file" ]]; then
	        continue
	    fi
	    
	    declare -A SEQUENCES
	    declare -A PROCESSED_INDIVS
	    TOTAL_INGROUP_INDIVS=0
	    SEQUENCE_LENGTH=0
	    
	    CURRENT_INDIV=""
	    CURRENT_SEQ=""
	    
	    while IFS= read -r line || [[ -n "$line" ]]; do
	        if [[ "$line" =~ ^\> ]]; then
	            if [[ -n "$CURRENT_INDIV" && -n "$CURRENT_SEQ" ]]; then
	                SEQUENCES["$CURRENT_INDIV"]="$CURRENT_SEQ"
	                if [[ $SEQUENCE_LENGTH -eq 0 ]]; then
	                    SEQUENCE_LENGTH=${#CURRENT_SEQ}
	                fi
	            fi
	            
	            CURRENT_INDIV="${line:1}"
	            CURRENT_INDIV=$(echo "$CURRENT_INDIV" | awk '{print $1}')
	            CURRENT_SEQ=""
	        else
	            CURRENT_SEQ="${CURRENT_SEQ}${line}"
	        fi
	    done < "$fasta_file"
	    
	    if [[ -n "$CURRENT_INDIV" && -n "$CURRENT_SEQ" ]]; then
	        SEQUENCES["$CURRENT_INDIV"]="$CURRENT_SEQ"
	        if [[ $SEQUENCE_LENGTH -eq 0 ]]; then
	            SEQUENCE_LENGTH=${#CURRENT_SEQ}
	        fi
	    fi
	    
	    INGROUP_DATA=()
	    for species in "${!SPECIES_INDIVS[@]}"; do
	        for individual in ${SPECIES_INDIVS["$species"]}; do
	            if [[ -n "${SEQUENCES[$individual]}" ]]; then
	                BPP_SEQ_NAME="${species}^${individual}"
	                INGROUP_DATA+=("$BPP_SEQ_NAME" "${SEQUENCES[$individual]}")
	                PROCESSED_INDIVS["$individual"]=1
	                TOTAL_INGROUP_INDIVS=$((TOTAL_INGROUP_INDIVS + 1))
	            fi
	        done
	    done
	    
	    if [[ $TOTAL_INGROUP_INDIVS -lt 2 ]]; then
	        echo "    ✗ SKIP - Only $TOTAL_INGROUP_INDIVS ingroup individual(s) found (minimum 2 required)" 
	        continue
	    fi
	    
	    {
	        # PHYLIP header: <number_of_sequences> <sequence_length>
	        echo " $TOTAL_INGROUP_INDIVS $SEQUENCE_LENGTH"
	        
	        for ((i=0; i<${#INGROUP_DATA[@]}; i+=2)); do
	            SEQ_NAME="${INGROUP_DATA[i]}"
	            SEQ_DATA="${INGROUP_DATA[i+1]}"
	            
	            printf "%-15s%s\n" "$SEQ_NAME" "$SEQ_DATA"
	        done
	    } >> "$SEQ_FILE"
	    
	    LOCUS_COUNT=$((LOCUS_COUNT + 1))
	    
	    unset SEQUENCES
	    unset PROCESSED_INDIVS
	    unset INGROUP_DATA
	done
	echo "Phylip file for BPP: $SEQ_FILE"
else
    echo "PHYLIP file for BPP: $PHYLIP_FILE"
    if [[ ! -s "$PHYLIP_FILE" ]]; then
        echo "Error: PHYLIP file is empty!"
        exit 1
    fi
    LOCUS_COUNT=0
    
    while IFS= read -r line; do
        # Skip empty lines and comment lines
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        # Check if this is a header line (starts with spaces/numbers)
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9]+ ]]; then
            # This is a locus header line
            LOCUS_COUNT=$((LOCUS_COUNT + 1))

        if [[ "$SKIP_VALIDATION" == true ]]; then
			continue
		fi 
            
        # Basic format validation: should contain sequence name and data
		elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([ACGTNacgtn-]+) ]]; then
			SEQ_NAME="${BASH_REMATCH[1]}"

			if [[ ! "$SEQ_NAME" =~ ^[^^]+\^[^^]+$ ]]; then
                echo "Error: Invalid sequence name format '$SEQ_NAME, Expected format: species^individual"
				exit
            fi
			SPECIES_NAME="${SEQ_NAME%^*}"
			INDIVIDUAL_NAME="${SEQ_NAME#*^}"
			if [[ -z INDIV_TO_SPECIES["$INDIVIDUAL_NAME"] || ${INDIV_TO_SPECIES["$INDIVIDUAL_NAME"]} != "$SPECIES_NAME" ]]; then
            	echo "Error: Invalid sequence name format '$SEQ_NAME: Individual '$INDIVIDUAL_NAME' not found in IMAP file, or '$INDIVIDUAL_NAME' does not match '$SPECIES_NAME'"
				exit
            fi
        fi
        
    done < "$PHYLIP_FILE"
	SEQ_FILE=$PHYLIP_FILE
fi
echo "Number of loci : $LOCUS_COUNT"

################# generating BPP ctl file ###################
echo ""
echo "Step 5: Generating BPP control file template..."
CTL_FILE="${PREFIX}_bpp.ctl"

S=$(( ${#SPECIES_INDIVS[@]} + 1 ))
line1="$S Ghost"
line2="0"
for species in "${!SPECIES_INDIVS[@]}"; do
    line1="$line1 $species"
	indiv_count=$(echo "${SPECIES_INDIVS["$species"]}" | wc -w)
	line2="$line2 $indiv_count"
done

new_Stree=$TREE_CONTENT
Ghost_pos=$(echo $new_Stree | nw_clade - $ANCHOR_P1 $ANCHOR_P2 $ANCHOR_P3 2>/dev/null)
Ghost_pos=${Ghost_pos%;}
new_Stree=${new_Stree/"$Ghost_pos"/"(Ghost,$Ghost_pos)gh"}

P1_P2=$(echo $new_Stree | nw_clade - $ANCHOR_P1 $ANCHOR_P2  2>/dev/null)
P1_P2=${P1_P2%;}
new_Stree=${new_Stree/"$P1_P2"/$P1_P2"P1_P2"}

P1_P3=$(echo $new_Stree | nw_clade - $ANCHOR_P1 $ANCHOR_P3 2>/dev/null)
P1_P3=${P1_P3%;}
new_Stree=${new_Stree/"$P1_P3"/$P1_P3"P1_P3"}

if [[ "$best_p1" == *","* ]]; then
    best_p1_no_comma=${best_p1//,/ }
    P1=$(echo "$new_Stree" | nw_clade - $best_p1_no_comma 2>/dev/null)
    P1=${P1%;}
    new_Stree=${new_Stree//"$P1"/"$P1""P1"}
	P1="P1"
else
    P1="$ANCHOR_P1"
fi

if [[ "$best_p2" == *","* ]]; then
    best_p2_no_comma=${best_p2//,/ }
    P2=$(echo "$new_Stree" | nw_clade - $best_p2_no_comma 2>/dev/null)
    P2=${P2%;}
    new_Stree=${new_Stree//"$P2"/"$P2""P2"}
	P2="P2"
else
    P2="$ANCHOR_P2"
fi

if [[ "$best_p3" == *","* ]]; then
    best_p3_no_comma=${best_p3//,/ }
    P3=$(echo "$new_Stree" | nw_clade - $best_p3_no_comma 2>/dev/null)
    P3=${P3%;}
    new_Stree=${new_Stree//"$P3"/"$P3""P3"}
	P3="P3"
else
    P3="$ANCHOR_P3"
fi
#echo "$new_Stree"

# constructe network model
MSCI_FILE=${PREFIX}_msci.txt
cat > "$MSCI_FILE" << EOF
tree $new_Stree
hybridization gh Ghost, P1_P2 $P1 as S H tau=no, yes phi=0.10
bidirection  P1_P2 $P2, P1_P3 $P3 as Z W phi=0.10,0.10
EOF

MODEL=$(bpp --msci-creat $MSCI_FILE 2>/dev/null | sed -n '$p')
rm $MSCI_FILE
PHASE=$(printf '0 %.0s' $(seq 1 $S) | sed 's/ $//')

cat > "$CTL_FILE" << EOF
          seed =  -1

       seqfile = $SEQ_FILE
      Imapfile = $IMAP_BPP
       jobname = ${PREFIX}

 speciesdelimitation = 0
         speciestree = 0

  species&tree = $line1
                   $line2
				 $MODEL
       usedata = 1
         nloci = $LOCUS_COUNT *The number can be reduced to use fewer loci
         phase = $PHASE *Need to adjust according to your specific data situation

	thetaprior = gamma 2 200  *Gamma(α,β) with the mean of α/β, The value of β can be adjusted to bring the mean into a reasonable range
	  tauprior = gamma 2 67 *Root time, Gamma(α,β) with the mean of α/β, The value of β can be adjusted to bring the mean into a reasonable range.
	  phiprior = 1 1 

	  finetune =  1
       *Threads = 8 19 1
	     print = 1 0 0 0
	    burnin = 100000 * Need to adjust according to according to your data size and the number of specified introgression events
	  sampfreq = 2
	   nsample = 300000 * Need to adjust according to according to your data size and the number of specified introgression events
EOF
echo "Control file for BPP: $CTL_FILE"
echo "Note: Remember to edit the $CTL_FILE file and adjust the parameter settings: nloci, phase, Threads, thetaprior, tauprior, burnin, nsample !"
#NOTE

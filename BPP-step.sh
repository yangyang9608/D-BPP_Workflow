#!/usr/bin/env bash
# By: Xiao-xu Pang, 2025-12-6

set -o pipefail

usage() {
    local status="${1:-1}"
    echo "Usage: bash $0 (--fasta_dir <fasta_directory> | --phylip_file <phylip_file>) --imap <imap_file> --tree <tree_file> --dstat <dstat_file> --prefix <output_prefix>"
    echo ""
	echo "Required parameters (choose one input type):"
    echo "  --fasta_dir <dir>     Directory containing locus FASTA files (.fa, .fas, .fasta)"
    echo "  --phylip_file <file>  BPP-PHYLIP file (user-prepared, or generated from previous BPP-step.sh run)"
    echo ""
    echo "Other required parameters:"
    echo "  --imap <file>         Individual to species mapping file (tab-delimited)"
    echo "  --tree <file>         Species tree file: output *tree file from D-step.sh"
    echo "  --dstat <file>        D-statistic results file: output *sig-triples file from D-step.sh"
    echo "  --prefix <prefix>     Output prefix for BPP files (assign unique names for each BPP analysis round, e.g., BPP-step/Sig-BPP-step1, BPP-step/Sig-BPP-step2...)"
    echo ""
	echo "Optional parameters:"
	echo "  --last_step           Output prefix from the last step, for identifying the BPP output files"
	echo "  --eps                 epsilon value for calculating the B10 value (Default: 0.001; only with --last_step)"
	echo "  --b10_cutoff          B10 cutoff for significant introgressions in BPP analysis (Default: 100; only with --last_step)"
    echo "  --skip_validation     Skip PHYLIP file format validation (only with --phylip_file)"
    echo "  --fbranch             Implement the fbranch rule for the consideration of ancestral gene flow"
	echo ""
	echo "############## Usage ############"
	echo "First step:"     
	echo "	bash $0 (--fasta_dir <fasta_directory> | --phylip_file <phylip_file>) --imap <imap_file> --tree <tree_file> --dstat <dstat_file> --prefix <output_prefix> [--fbranch]"
	echo "Subsequent steps:" 
	echo  "	bash $0 --phylip_file <phylip_file> --imap <imap_file> --tree <tree_file> --dstat <dstat_file> --prefix <output_prefix>  --last_step <output_prefix_of_last_step> --skip_validation  [--fbranch] [--eps <epsilon_value>] [--b10_cutoff <b10_cutoff_value>]"
	echo ""
	echo "############# Example ###########"
	echo "bash $0 --fasta_dir ./fasta_dir/ --imap test.imap --tree D-step/Sig-D-Tree1.tree --dstat D-step/Sig-D-Tree1.sig-triples --prefix BPP-step/Sig-BPP-step1 2> BPP-step/Sig-BPP-step1.log"
	echo "bash $0 --phylip_file BPP-step/BPP.phy --imap test.imap --tree D-step/Sig-D-Tree1.tree --dstat D-step/Sig-D-Tree1.sig-triples --prefix BPP-step/Sig-BPP-step2 --last_step BPP-step/Sig-BPP-step1 --skip_validation 2>BPP-step/Sig-BPP-step2.log"
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

if [[ $# -eq 0 ]]; then
    usage 1
fi

SKIP_VALIDATION=false
FBRANCH=false
EPS=0.001
B10_CUTOFF=100
while [[ $# -gt 0 ]]; do
    case $1 in
        --fasta_dir)
            require_value "$1" "${2-}"
            FASTA_DIR="$2"
            shift 2
            ;;
        --phylip_file)
            require_value "$1" "${2-}"
            PHYLIP_FILE="$2"
            shift 2
            ;;
        --imap)
            require_value "$1" "${2-}"
            IMAP_FILE="$2"
            shift 2
            ;;
        --tree)
            require_value "$1" "${2-}"
            TREE_FILE="$2"
            shift 2
            ;;
        --dstat)
            require_value "$1" "${2-}"
            DSTAT_FILE="$2"
            shift 2
            ;;
        --prefix)
            require_value "$1" "${2-}"
            PREFIX="$2"
            shift 2
            ;;
		--last_step)
			require_value "$1" "${2-}"
			LAST_STEP="$2"
			shift 2
			;;
		--eps)
			require_value "$1" "${2-}"
			EPS="$2"
			shift 2
			;;
		--esp)
			require_value "$1" "${2-}"
			EPS="$2"
			echo "WARNING: --esp is deprecated; use --eps" >&2
			shift 2
			;;
		--b10_cutoff)
			require_value "$1" "${2-}"
			B10_CUTOFF="$2"
			shift 2
			;;
		--skip_validation)
            SKIP_VALIDATION=true
            shift 
            ;;
		--fbranch)
			FBRANCH=true
			shift
			;;
        -h|--help)
            usage 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage 1
            ;;
    esac
done

#====================check input files==========================
if [[ -n "$FASTA_DIR" && -n "$PHYLIP_FILE" ]]; then
    echo "ERROR: Cannot specify both --fasta_dir and --phylip_file" >&2
    usage 1
elif [[ -z "$FASTA_DIR" && -z "$PHYLIP_FILE" ]]; then
    echo "ERROR: Must specify either --fasta_dir or --phylip_file" >&2
    usage 1
elif [[ -n "$FASTA_DIR" && ! -d "$FASTA_DIR" ]]; then
    die "FASTA directory '$FASTA_DIR' does not exist"
elif [[ -n "$PHYLIP_FILE" && ! -f "$PHYLIP_FILE" ]]; then
    die "PHYLIP file '$PHYLIP_FILE' does not exist"
fi

if [[ "$SKIP_VALIDATION" == true && -z "$PHYLIP_FILE" ]]; then
    echo "ERROR: --skip_validation can only be used with --phylip_file" >&2
    usage 1
fi
if [[ -z "$IMAP_FILE" || -z "$TREE_FILE" || -z "$DSTAT_FILE" || -z "$PREFIX" ]]; then
    echo "ERROR: Missing required parameters!" >&2
    usage 1
fi

for file in "$IMAP_FILE" "$TREE_FILE" "$DSTAT_FILE"; do
    if [[ ! -f "$file" ]]; then
        die "Input file '$file' does not exist"
    fi
done

if [[ -n "${LAST_STEP+x}" ]]; then
    if [[ -z "$LAST_STEP" ]]; then
        die "Missing --last_step value"
    fi
    if [[ ! -f "${LAST_STEP}.introgression" ]] || [[ ! -f "${LAST_STEP}.mcmc.txt" ]]; then
        echo "ERROR: Required files not found:" >&2
        [[ ! -f "${LAST_STEP}.introgression" ]] && echo "  - ${LAST_STEP}.introgression" >&2 
        [[ ! -f "${LAST_STEP}.mcmc.txt" ]] && echo "  - ${LAST_STEP}.mcmc.txt" >&2
        exit 1
    fi
	INTR_FILE=${LAST_STEP}.introgression
	MCMC_FILE=${LAST_STEP}.mcmc.txt
fi

if ! [[ "$EPS" =~ ^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]; then
    die "--eps must be numeric (received '$EPS')"
fi
awk -v value="$EPS" 'BEGIN { exit !(value > 0 && value < 1) }' || \
    die "--eps must be greater than 0 and less than 1 (received '$EPS')"

if ! [[ "$B10_CUTOFF" =~ ^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]; then
    die "--b10_cutoff must be numeric (received '$B10_CUTOFF')"
fi
awk -v value="$B10_CUTOFF" 'BEGIN { exit !(value > 0) }' || \
    die "--b10_cutoff must be greater than 0 (received '$B10_CUTOFF')"

for command_name in bpp nw_display nw_clade nw_labels nw_prune perl; do
    require_command "$command_name"
done

PREFIX_DIR=$(dirname "$PREFIX")
mkdir -p "$PREFIX_DIR" || die "Failed to create output directory '$PREFIX_DIR'"


step=1
#============================================================
# read imap file
echo "=================================================" >&2
echo "Step $step: Reading IMAP file and identifying outgroup..." >&2
declare -A INDIV_TO_SPECIES
declare -A SPECIES_INDIVS
declare -A SEEN_SPECIES
declare -a SPECIES_ORDER
OUTGROUP_INDS=()
IMAP_BPP="${PREFIX_DIR}/BPP.imap"

> "$IMAP_BPP"
IMAP_LINE=0
while read -r individual species extra || [[ -n "$individual" ]]; do
    ((IMAP_LINE++))
    [[ -z "$individual" || "$individual" == \#* ]] && continue
    [[ -n "$species" && -z "$extra" ]] || die "Malformed IMAP line $IMAP_LINE; expected exactly two whitespace-delimited columns"
    [[ -z "${INDIV_TO_SPECIES[$individual]}" ]] || die "Duplicate individual '$individual' in IMAP file"
    INDIV_TO_SPECIES["$individual"]="$species"

    if [[ "$species" == "Outgroup" ]]; then
        OUTGROUP_INDS+=("$individual")
    else
		printf '%s\t%s\n' "$individual" "$species" >> "$IMAP_BPP"
        if [[ -z "${SEEN_SPECIES[$species]}" ]]; then
            SEEN_SPECIES["$species"]=1
            SPECIES_ORDER+=("$species")
        fi
        if [[ -z "${SPECIES_INDIVS[$species]}" ]]; then
            SPECIES_INDIVS["$species"]="$individual"
        else
            SPECIES_INDIVS["$species"]="${SPECIES_INDIVS[$species]} $individual"
        fi
    fi
done < "$IMAP_FILE"

[[ ${#INDIV_TO_SPECIES[@]} -gt 0 ]] || die "IMAP file contains no samples"
[[ ${#SPECIES_ORDER[@]} -ge 3 ]] || die "BPP-step requires at least three ingroup species"

echo "Outgroup individuals: ${#OUTGROUP_INDS[@]}" >&2
echo "Ingroup species: ${SPECIES_ORDER[*]}" >&2
echo "BPP imap file: $IMAP_BPP" >&2
((step++))

#============================================================
# generating Phylip file
echo "" >&2
echo "=================================================" >&2
echo "Step $step: Processing or checking BPP PHYLIP file..." >&2

SEQ_FILE="${PREFIX_DIR}/BPP.phy"
LOCUS_COUNT=0

if [[ -n "$FASTA_DIR" ]]; then
    echo "FASTA directory: $FASTA_DIR" >&2
    
	> "$SEQ_FILE"
	
		FASTA_FILE_COUNT=0
		for fasta_file in "$FASTA_DIR"/*.fasta "$FASTA_DIR"/*.fa "$FASTA_DIR"/*.fas; do
		    if [[ ! -f "$fasta_file" ]]; then
		        continue
		    fi
		    ((FASTA_FILE_COUNT++))

		    declare -A SEQUENCES=()
		    TOTAL_INGROUP_INDIVS=0
		    SEQUENCE_LENGTH=0
	    
	    CURRENT_INDIV=""
	    CURRENT_SEQ=""
	    
		    while IFS= read -r line || [[ -n "$line" ]]; do
		        if [[ "$line" =~ ^\> ]]; then
		            if [[ -n "$CURRENT_INDIV" ]]; then
		                [[ -n "$CURRENT_SEQ" ]] || die "Empty sequence for '$CURRENT_INDIV' in '$fasta_file'"
		                [[ -z "${SEQUENCES[$CURRENT_INDIV]}" ]] || die "Duplicate FASTA identifier '$CURRENT_INDIV' in '$fasta_file'"
		                SEQUENCES["$CURRENT_INDIV"]="$CURRENT_SEQ"
		                if [[ $SEQUENCE_LENGTH -eq 0 ]]; then
		                    SEQUENCE_LENGTH=${#CURRENT_SEQ}
		                elif [[ ${#CURRENT_SEQ} -ne $SEQUENCE_LENGTH ]]; then
		                    die "Sequences are not aligned to a common length in '$fasta_file'"
		                fi
		            fi
	            
	            CURRENT_INDIV="${line:1}"
		            CURRENT_INDIV="${CURRENT_INDIV%%[[:space:]]*}"
		            [[ -n "$CURRENT_INDIV" ]] || die "Empty FASTA identifier in '$fasta_file'"
		            CURRENT_SEQ=""
		        elif [[ -n "$CURRENT_INDIV" ]]; then
		            line=$(printf '%s' "$line" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
		            [[ "$line" =~ ^[ACGTRYSWKMBDHVN?*-]*$ ]] || die "Unsupported sequence character for '$CURRENT_INDIV' in '$fasta_file'"
		            CURRENT_SEQ="${CURRENT_SEQ}${line}"
		        fi
		    done < "$fasta_file"

		    if [[ -n "$CURRENT_INDIV" ]]; then
		        [[ -n "$CURRENT_SEQ" ]] || die "Empty sequence for '$CURRENT_INDIV' in '$fasta_file'"
		        [[ -z "${SEQUENCES[$CURRENT_INDIV]}" ]] || die "Duplicate FASTA identifier '$CURRENT_INDIV' in '$fasta_file'"
		        SEQUENCES["$CURRENT_INDIV"]="$CURRENT_SEQ"
		        if [[ $SEQUENCE_LENGTH -eq 0 ]]; then
		            SEQUENCE_LENGTH=${#CURRENT_SEQ}
		        elif [[ ${#CURRENT_SEQ} -ne $SEQUENCE_LENGTH ]]; then
		            die "Sequences are not aligned to a common length in '$fasta_file'"
		        fi
		    fi

		    INGROUP_DATA=()
		    for species in "${SPECIES_ORDER[@]}"; do
	        for individual in ${SPECIES_INDIVS["$species"]}; do
	            if [[ -n "${SEQUENCES[$individual]}" ]]; then
	                BPP_SEQ_NAME="${species}^${individual}"
	                INGROUP_DATA+=("$BPP_SEQ_NAME" "${SEQUENCES[$individual]}")
		                TOTAL_INGROUP_INDIVS=$((TOTAL_INGROUP_INDIVS + 1))
	            fi
	        done
	    done
	    
		    if [[ $TOTAL_INGROUP_INDIVS -lt 2 ]]; then
		        echo "SKIP $(basename "$fasta_file"): only $TOTAL_INGROUP_INDIVS ingroup individual(s) found (minimum 2 required)" >&2
		        unset SEQUENCES INGROUP_DATA
		        continue
	    fi
	    
	    {
	        # PHYLIP header: <number_of_sequences> <sequence_length>
	        echo " $TOTAL_INGROUP_INDIVS $SEQUENCE_LENGTH"
	        
	        for ((i=0; i<${#INGROUP_DATA[@]}; i+=2)); do
	            SEQ_NAME="${INGROUP_DATA[i]}"
	            SEQ_DATA="${INGROUP_DATA[i+1]}"
	            
		            printf "%s  %s\n" "$SEQ_NAME" "$SEQ_DATA"
	        done
	    } >> "$SEQ_FILE"
	    
	    LOCUS_COUNT=$((LOCUS_COUNT + 1))
	    
	    unset SEQUENCES
	    unset INGROUP_DATA
		done
		[[ $FASTA_FILE_COUNT -gt 0 ]] || die "No .fa, .fas, or .fasta files were found in '$FASTA_DIR'"
		[[ $LOCUS_COUNT -gt 0 ]] || die "No FASTA locus contained at least two ingroup individuals"
		echo "Phylip file for BPP: $SEQ_FILE" >&2
else
    echo "PHYLIP file for BPP: $PHYLIP_FILE" >&2
    if [[ ! -s "$PHYLIP_FILE" ]]; then
        die "PHYLIP file '$PHYLIP_FILE' is empty"
    fi
    if [[ "$SKIP_VALIDATION" == true ]]; then
        LOCUS_COUNT=$(awk '$0 ~ /^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]*$/ { count++ } END { print count + 0 }' "$PHYLIP_FILE")
    else
        LOCUS_COUNT=0
        EXPECTED_SEQUENCES=0
        EXPECTED_LENGTH=0
        OBSERVED_SEQUENCES=0
        declare -A SEEN_PHYLIP_NAMES=()

        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
                if [[ $LOCUS_COUNT -gt 0 && $OBSERVED_SEQUENCES -ne $EXPECTED_SEQUENCES ]]; then
                    die "PHYLIP locus $LOCUS_COUNT declares $EXPECTED_SEQUENCES sequences but contains $OBSERVED_SEQUENCES"
                fi
                ((LOCUS_COUNT++))
                EXPECTED_SEQUENCES=${BASH_REMATCH[1]}
                EXPECTED_LENGTH=${BASH_REMATCH[2]}
                OBSERVED_SEQUENCES=0
                SEEN_PHYLIP_NAMES=()
                [[ $EXPECTED_SEQUENCES -ge 2 && $EXPECTED_LENGTH -gt 0 ]] || die "Invalid PHYLIP header for locus $LOCUS_COUNT"
                continue
            fi

            [[ $LOCUS_COUNT -gt 0 ]] || die "PHYLIP sequence encountered before the first locus header"
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([ACGTRYSWKMBDHVNacgtryswkmbdhvn?*-]+)[[:space:]]*$ ]]; then
                SEQ_NAME="${BASH_REMATCH[1]}"
                SEQ_DATA="${BASH_REMATCH[2]}"
                [[ "$SEQ_NAME" =~ ^[^^]+\^[^^]+$ ]] || die "Invalid sequence name '$SEQ_NAME'; expected species^individual"
                [[ -z "${SEEN_PHYLIP_NAMES[$SEQ_NAME]}" ]] || die "Duplicate sequence '$SEQ_NAME' in PHYLIP locus $LOCUS_COUNT"
                [[ ${#SEQ_DATA} -eq $EXPECTED_LENGTH ]] || die "Sequence '$SEQ_NAME' in PHYLIP locus $LOCUS_COUNT has length ${#SEQ_DATA}; expected $EXPECTED_LENGTH"
                SPECIES_NAME="${SEQ_NAME%^*}"
                INDIVIDUAL_NAME="${SEQ_NAME#*^}"
                if [[ -z "${INDIV_TO_SPECIES[$INDIVIDUAL_NAME]}" || "${INDIV_TO_SPECIES[$INDIVIDUAL_NAME]}" != "$SPECIES_NAME" ]]; then
                    die "Sequence '$SEQ_NAME' does not match the IMAP assignment for '$INDIVIDUAL_NAME'"
                fi
                SEEN_PHYLIP_NAMES["$SEQ_NAME"]=1
                ((OBSERVED_SEQUENCES++))
                [[ $OBSERVED_SEQUENCES -le $EXPECTED_SEQUENCES ]] || die "PHYLIP locus $LOCUS_COUNT contains more sequences than declared"
            else
                die "Unrecognized PHYLIP line: '$line' (use --skip_validation only after validating the file independently)"
            fi
        done < "$PHYLIP_FILE"

        if [[ $LOCUS_COUNT -gt 0 && $OBSERVED_SEQUENCES -ne $EXPECTED_SEQUENCES ]]; then
            die "PHYLIP locus $LOCUS_COUNT declares $EXPECTED_SEQUENCES sequences but contains $OBSERVED_SEQUENCES"
        fi
    fi
	SEQ_FILE=$PHYLIP_FILE
fi
[[ $LOCUS_COUNT -gt 0 ]] || die "No PHYLIP locus headers were found"
echo "Number of loci : $LOCUS_COUNT" >&2
((step++))

#====================================================================
#read tree topology
echo "" >&2
echo "================================================="  >&2
echo "Step $step: Reading tree file..." >&2
if [[ -f "$TREE_FILE" ]]; then
	TREE_CONTENT=$(tr -d '[:space:]' < "$TREE_FILE")
	if if_tree=$(printf '%s\n' "$TREE_CONTENT" | nw_display - 2>/dev/null) && [[ -n "$(printf '%s' "$if_tree" | tr -d '[:space:]')" ]]; then
		# add inner-node labels
		tree=$(printf '%s\n' "$TREE_CONTENT" | perl -pe 's/:-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?//g')
		node_id=1
		new_tree=""
		i=0
		len=${#tree}
		
		while [ $i -lt $len ]; do
		    char=${tree:$i:1}
		    new_tree+="$char"
		
		    if [ "$char" = ")" ]; then
		        ((i++))
		        next_char=${tree:$i:1}
		
		        if [[ "$next_char" =~ ^[\),\;]$ ]]; then
		            new_tree+="N${node_id}"
		            ((node_id++))
		            ((i--))
		        fi
		    fi

    		((i++))
		done
		echo "Tree topology: $new_tree" >&2
	else
		die "Invalid Newick tree in '$TREE_FILE'"
	fi
fi
((step++))

#====================================================================
# read output files of the last step
# function for getting the parental node for a given node
find_parent_node() {
	local topo="$1"
	local node="$2"			

	local right_topo=$(echo "$topo" | perl -spe 's/.*([,()])\Q$node\E([,()\;].*)/$2/' -- -node="$node")

	local num_left=0    
    local num_right=0   
    local p_node=""     
    local collecting=0  
    
    for ((i=0; i<${#right_topo}; i++)); do
        local char="${right_topo:$i:1}"
        
        if [[ "$char" == "(" ]]; then
            ((num_left++))
        elif [[ "$char" == ")" ]]; then
            ((num_right++))
            
            if [[ $num_right -gt $num_left && $collecting -eq 0 ]]; then
				collecting=1
				continue
            fi
        fi
		if [[ $collecting -eq 1 ]]; then
            if [[ "$char" != ")" && "$char" != "," && "$char" != "(" && "$char" != ";" ]]; then
                p_node="${p_node}${char}"
			else
				break
            fi
        fi
    done

	echo "$p_node"
} 
#find_parent_node "$new_tree" "N4"

# function for getting the children node for a given node
find_children_node() {
	local topo="$1"
	local node="$2"			

	local left_topo=$(echo "$topo" | perl -spe 's/(.*[,()])\Q$node\E([,()\;].*)/$1/' -- -node="${node}")

	local num_left=0    
    local num_right=0   
    local c_node1=""     
    local c_node2=""     
    local collecting1=1  
    local collecting2=0  
   	
	if [[ "${left_topo: -1}" == ")" ]]; then
	    for ((i=1; i<${#left_topo}; i++)); do
			local j=$((${#left_topo}-1-$i))
	        local char="${left_topo:$j:1}"
			if [[ $collecting1 -eq 1 ]]; then
				if [[ "$char" != ")" && "$char" != "," && "$char" != "(" && "$char" != ";" ]]; then
					c_node1="${char}${c_node1}"
					continue
				else
					collecting1=0
					if [[ "$char" == "," ]]; then
						collecting2=1
					fi
					continue
				fi
			fi
			
			if [[ $collecting2 -eq 1 ]]; then
	            if [[ "$char" != ")" && "$char" != "," && "$char" != "(" && "$char" != ";" ]]; then
	                c_node2="${char}${c_node2}"
					continue
				else
					break
	            fi
	        fi
	
	        if [[ "$char" == "(" ]]; then
	            ((num_left++))
	            if [[ $num_right -lt $num_left ]]; then
					collecting2=1
					((i++))
					continue
            	fi
        	elif [[ "$char" == ")" ]]; then
            	((num_right++))
        	fi
    	done
	fi

	local child=($c_node1 $c_node2)
	echo "${child[@]}"
} 
#find_children_node "(Ghost1,((Ghost2,((A,B)N1,C)N2)N6,(D,E)N3)N4)N5;" "N6"

# function for getting the hybrid cycle for a given introgression
find_cycle() {
	local tree=$1
	local int=$2	
	[[ "$int" =~ .*/(.*)\<--.*/(.*) ]]
	local node1=${BASH_REMATCH[1]}
	local node2=${BASH_REMATCH[2]}
	local path1=("$node1")
	local path2=("$node2")
	local current=$node1
	while [[ -n $(find_parent_node "$tree" "$current") ]]; do
        current=$(find_parent_node "$tree" "$current")
        path1=("${path1[@]}" "$current")
    done

	current=$node2
	while [[ -n $(find_parent_node "$tree" "$current") ]]; do
        current=$(find_parent_node "$tree" "$current")
        path2=("${path2[@]}" "$current")
    done

	for ((i=1; i<${#path1[@]}; i++)); do
        local n1="${path1[i]}"
        for ((j=1; j<${#path2[@]}; j++)); do
        	local n2="${path2[j]}"
            if [[ "$n1" == "$n2" ]]; then
				path1=("${path1[@]:0:$i}")
				path2=("${path2[@]:0:$j}")
				break 2
            fi
        done
    done

	local cycle=("${path1[@]}" "${path2[@]}")
	declare -A assoc && for item in "${cycle[@]}"; do assoc["$item"]=1; done
	local -A cycle_child
	for node in "${cycle[@]}"; do
		local child=$(find_children_node "$tree" "$node")
		#echo "$node: $child" >&2
		if [[ -n "$child" ]];then
			read -r c1 c2 <<< "$child"
			if [[ -z "${assoc["$c1"]}" ]]; then
				cycle_child[$node]=$c1
			else
				cycle_child[$node]=$c2
			fi
		else
			cycle_child[$node]=$node
		fi
		local leaf=$(echo "$tree" | nw_clade - "${cycle_child[$node]}" |nw_labels - -I | tr "\n" " " | sed 's/ $//')
		echo "$node: $leaf"
		[[ $node == ${path1[-1]} ]] && echo ""
	done

}

# generate the explained triples for a given hybrid cycle
explained_triples() {
	local input="$1"
	local section=0  # 0: hybrid side, 1: donor side
	local -A hybrid_side=()
	local -A donor_side=()
	local hybrid_node=""
	local hybrid_leaf=""
	local hybrid_side_order=()
	local donor_side_order=()
	
	# parse input
	local OLDIFS="$IFS"
	IFS=$'\n'
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
			section=1
			continue
		fi
		
		if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
			node="${BASH_REMATCH[1]}"
			leaves="${BASH_REMATCH[2]}"
			
			if [[ $section -eq 0 ]]; then
				# hybrid side
				if [[ -z "$hybrid_node" ]]; then
					hybrid_node="$node"
					hybrid_side["$node"]="$leaves"
				else
					hybrid_side["$node"]="$leaves"
					hybrid_side_order+=("$node")
				fi
			else
				# donor side
				if ! [[ "$node" =~ ^Ghost ]]; then
					donor_side["$node"]="$leaves"
					donor_side_order+=("$node")
				fi
			fi
		fi
	done <<< "$input"
	
	IFS="$OLDIFS"

	# generate explained triples
	local explained_triples=()	
	IFS=' ' read -ra hybrid_node_leaves <<< "${hybrid_side[$hybrid_node]}"
	
	# triple: 1-H-2 
	for hybrid_leaf in "${hybrid_node_leaves[@]}"; do
		for h_node in "${hybrid_side_order[@]}"; do
			IFS=' ' read -ra h_leaves <<< "${hybrid_side[$h_node]}"
			for d_node in "${donor_side_order[@]}"; do
				IFS=' ' read -ra d_leaves <<< "${donor_side[$d_node]}"
				for h_leaf in "${h_leaves[@]}"; do
					for d_leaf in "${d_leaves[@]}"; do
						explained_triples+=("$h_leaf,$hybrid_leaf,$d_leaf")
					done
				done
			done
		done
	done
	
	# triple: H-1-1
	for hybrid_leaf in "${hybrid_node_leaves[@]}"; do
		for ((i=0; i<${#hybrid_side_order[@]}; i++)); do
			for ((j=i+1; j<${#hybrid_side_order[@]}; j++)); do
				node_i="${hybrid_side_order[i]}"
				node_j="${hybrid_side_order[j]}"
				IFS=' ' read -ra leaves_i <<< "${hybrid_side[$node_i]}"
				IFS=' ' read -ra leaves_j <<< "${hybrid_side[$node_j]}"
				for leaf_i in "${leaves_i[@]}"; do
					for leaf_j in "${leaves_j[@]}"; do
						explained_triples+=("$hybrid_leaf,$leaf_i,$leaf_j")
					done
				done
			done
		done
	done	

	# triple: 2-2-H
	for hybrid_leaf in "${hybrid_node_leaves[@]}"; do
		for ((i=0; i<${#donor_side_order[@]}; i++)); do
			for ((j=i+1; j<${#donor_side_order[@]}; j++)); do
				node_i="${donor_side_order[i]}"
				node_j="${donor_side_order[j]}"
				IFS=' ' read -ra leaves_i <<< "${donor_side[$node_i]}"
				IFS=' ' read -ra leaves_j <<< "${donor_side[$node_j]}"
				for leaf_i in "${leaves_i[@]}"; do
					for leaf_j in "${leaves_j[@]}"; do
						explained_triples+=("$leaf_j,$leaf_i,$hybrid_leaf")
					done
				done
			done
		done
	done
	
	echo "${explained_triples[@]}"	
}

# read BPP output files in the last step
declare -A adding_intro
declare -a adding_intro_sort

# function for constructing the ctl file
ctl_con() {
	declare -g -a msci_command
	declare -g -a intr_log
	declare -g -A conflicting
	declare -g -a warning
	declare -g hybrid_id=0
	msci_command=()
	intr_log=()
	conflicting=()
	warning=()
	#arrange introgression edges to the backbone tree
	for key in "${adding_intro_sort[@]}"; do
		[[ $key =~ ^(.+)/([^<]+)(<?)--\>(.+)/(.+)$ ]] || die "Could not parse introgression edge '$key'"
		n1=${BASH_REMATCH[1]}
		n2=${BASH_REMATCH[2]}
	    if_bi=${BASH_REMATCH[3]}
	    n3=${BASH_REMATCH[4]}
	    n4=${BASH_REMATCH[5]}
	
		if [[ -z ${conflicting[$n2]} ]];then
			conflicting[$n2]=$n2
		else
			warning+=("Warning: multiple introgression edges involve the tree edge $n1/$n2, please check and adjust the ${PREFIX}.msci and ${PREFIX}.introgression")
		fi
		if [[ -z ${conflicting[$n4]} ]];then
			conflicting[$n4]=$n4
		else
			warning+=("Warning: multiple introgression edges involve the tree edge $n3/$n4, please check and adjust the ${PREFIX}.msci and ${PREFIX}.introgression")
		fi
		
		if [[ -z $if_bi ]];then
			command="hybridization $n1 ${conflicting[$n2]}, $n3 ${conflicting[$n4]} as Z$((hybrid_id + 1)) Z$((hybrid_id + 2)) tau=no, yes phi=0.10"
			type="hybridization"
			intr_log+=("	$n3/$n4<--$n1/$n2: Z$((hybrid_id + 2))<-Z$((hybrid_id + 1))")
		else
			command="bidirection $n1 ${conflicting[$n2]}, $n3 ${conflicting[$n4]} as Z$((hybrid_id + 1)) Z$((hybrid_id + 2))  phi=0.10,0.10"
			type="bidirection"
			intr_log+=("	$n3/$n4<--$n1/$n2: Z$((hybrid_id + 2))<-Z$((hybrid_id + 1))")
			intr_log+=("	$n1/$n2<--$n3/$n4: Z$((hybrid_id + 1))<-Z$((hybrid_id + 2))")
		fi
	
		conflicting[$n2]="Z$((hybrid_id + 1))"
		conflicting[$n4]="Z$((hybrid_id + 2))"
			
		((hybrid_id += 2))
		msci_command+=("$command")
		echo "$type: $key" >&2
	done
	declare -g merged_command=$(printf "%s\n" "${msci_command[@]}")
	declare -g merged_warning=$(printf "%s\n" "${warning[@]}")
	declare -g merged_intr_log=$(printf "%s\n" "${intr_log[@]}")
	[[ "$merged_warning" ]] && echo "" >&2 && echo "$merged_warning" >&2
	
	declare -g MSCI_FILE=${PREFIX}.msci
	cat > "$MSCI_FILE" << EOF
tree $new_tree
$merged_command
EOF
	if ! MSCI_OUTPUT=$(bpp --msci-create "$MSCI_FILE" 2>&1); then
		printf '%s\n' "$MSCI_OUTPUT" >&2
		die "BPP could not construct an MSCI model from '$MSCI_FILE'"
	fi
	MODEL=$(printf '%s\n' "$MSCI_OUTPUT" | tail -n 1)
	[[ -n "$MODEL" && ! "$MODEL" =~ ^Processing ]] || die "BPP did not return a valid MSCI model for '$MSCI_FILE'"

	################generate ctl file##################
	CTL_FILE="${PREFIX}.ctl"
	local -a GHOST_NAMES=()
	mapfile -t GHOST_NAMES < <(printf '%s\n' "$new_tree" | nw_labels - | grep -o -E 'Ghost[0-9]+' | sort -Vu)
	num_ghosts=${#GHOST_NAMES[@]}
	declare -g S=$(( ${#SPECIES_ORDER[@]} + num_ghosts ))

	declare -a ctl_species=("${GHOST_NAMES[@]}" "${SPECIES_ORDER[@]}")
	declare -a sample_counts=()
	declare -a phase_values=()
	for ((i = 0; i < num_ghosts; i++)); do
		sample_counts+=("0")
	done
	for species in "${SPECIES_ORDER[@]}"; do
		indiv_count=$(wc -w <<< "${SPECIES_INDIVS[$species]}")
		sample_counts+=("$indiv_count")
	done
	for ((i = 0; i < S; i++)); do
		phase_values+=("0")
	done
	line1="$S ${ctl_species[*]}"
	line2="${sample_counts[*]}"
	PHASE="${phase_values[*]}"
	
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
	        burnin = 100000 * Need to adjust according to your data size and the number of specified introgression events
	      sampfreq = 2
	       nsample = 300000 * Need to adjust according to your data size and the number of specified introgression events
EOF
	echo "" >&2
	echo "Control file for BPP: $CTL_FILE" >&2
	echo "Note: Remember to edit the $CTL_FILE file and adjust the parameter settings: nloci, phase, Threads, thetaprior, tauprior, burnin, nsample!" >&2
	echo "" >&2
	echo "=================================================" >&2
	echo "The next command: bpp --cfile $CTL_FILE" >&2
}

#: <<'NOTE'
if [[ -n "${LAST_STEP+x}" ]]; then
	echo "" >&2
	echo "=================================================" >&2
	echo "Step $step: Reading BPP output files in the last step..." >&2
	declare -A intr
	declare -a intr_sort
	in_intro=false
	while IFS= read -r line || [[ -n "$line" ]]; do
	    [[ -z "$line" ]] && continue
		if [[ "$line" =~ ^tree: ]]; then
			new_tree=$(echo "$line" | sed 's/^tree: //')
		fi

	    if [[ "$line" =~ ^introgression: ]]; then
	        in_intro=true
	        continue
	    fi
	    
	    if [[ "$in_intro" != true ]]; then
	        continue
	    fi
	    
	    if [[ "$line" =~ ^[[:space:]]*(.+):[[:space:]]*(.+)$ ]]; then
	        label="${BASH_REMATCH[2]}"
	        event="${BASH_REMATCH[1]}"
	        intr["$label"]="$event"
			intr_sort=("$label" "${intr_sort[@]}")
		fi
	done < "$INTR_FILE" # read the introgression file
	[[ -n "$new_tree" ]] || die "No 'tree:' entry was found in '$INTR_FILE'"
	[[ ${#intr[@]} -gt 0 ]] || die "No introgression entries were found in '$INTR_FILE'"

	#check whether the mcmc file  is empty 
	data_lines=$(awk 'NR > 1 && NF { count++ } END { print count + 0 }' "$MCMC_FILE")
	if [[ $data_lines -eq 0 ]]; then
		die "No data rows were found in '$MCMC_FILE' after the header"
	fi
	# read the header of the mcmc file
	if IFS= read -r header < "$MCMC_FILE"; then
	declare -A col_to_label
	read -ra columns <<< "$header"
	for idx in "${!columns[@]}"; do
		col="${columns[$idx]}"
		if [[ "$col" == phi:* ]]; then
			label="${col##*:}"
			col_to_label[$((idx+1))]="$label"
		elif [[ "$col" == phi_* ]]; then
			label="${col#phi_}"
			col_to_label[$((idx+1))]="$label"
		fi
	done
	fi
	[[ ${#col_to_label[@]} -gt 0 ]] || die "No phi columns were found in '$MCMC_FILE'"

	# calculate B10 and delete non-sig introgressions
	declare -A nonsig_int
	echo "Tree including ghost lineages: $new_tree" >&2
	echo "Supported introgression events in the last step:" >&2
	for i in "${!col_to_label[@]}"; do
		label="${col_to_label[$i]}"
		[[ -n "${intr[$label]}" ]] || die "Phi column '$label' has no matching entry in '$INTR_FILE'"
		B10=$(awk -v e="$EPS" -v i="$i" '
			NR > 1 && NF {
				value = $i
				if (value ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) {
					valid++
					if (value < e) below++
				}
			}
			END {
				if (valid == 0) print "NA"
				else if (below == 0) print "INF"
				else printf "%.10g", e / (below / valid)
			}
		' "$MCMC_FILE")
		[[ "$B10" != "NA" ]] || die "Phi column '$label' contains no numeric posterior samples"
		if [[ "$B10" != "INF" ]] && awk -v value="$B10" -v cutoff="$B10_CUTOFF" 'BEGIN { exit !(value < cutoff) }'; then
			nonsig_int["${intr[$label]}"]=1
			unset 'intr[$label]'
		fi
		[[ -n "${intr[$label]}" ]] && printf "%-30s B10:%-10s\n" "$label(${intr[$label]})" "$B10" >&2
	done

	for i in "${!intr_sort[@]}"; do
		[[ -n "${intr["${intr_sort[$i]}"]}" ]] && first=$i && break 
	done
	if [[ -z "$first" || $first -gt 2 ]]; then
		echo "Workflow complete: none of the three events added in the last round passed the B10 cutoff." >&2
		echo "Use the supported model from the preceding round." >&2
		exit 0
	fi

	for key in "${!nonsig_int[@]}"; do
		if [[ $key =~ (Ghost.*$) ]]; then
			new_tree=$(echo "$new_tree" |nw_prune - "${BASH_REMATCH[1]}")
		fi
	done

	#generate the explained triples
	declare -A explained_triples
	for key in "${!intr[@]}"; do
		int=${intr[$key]}
		cycle=$(find_cycle "$new_tree" "$int")	
		out=$(explained_triples "$cycle")
		IFS=' ' read -ra tris <<< "$out"
		for t in "${tris[@]}"; do
			explained_triples["$t"]=1
		done
	done

    #collecting added introgressions
	for key in "${!intr[@]}"; do
		int=${intr[$key]}
		[[ "$int" =~ (.*)/(.*)\<--(.*)/(.*) ]] || die "Could not parse introgression entry '$int'"
        n1=${BASH_REMATCH[1]}
        n2=${BASH_REMATCH[2]}
        n3=${BASH_REMATCH[3]}
        n4=${BASH_REMATCH[4]}
        if [[ $n4 =~ ^Ghost ]]; then 
            adding_intro["$n3/$n4-->$n1/$n2"]=1
        else 
            if [[ -n ${adding_intro["$n1/$n2-->$n3/$n4"]} ]]; then 
                unset adding_intro["$n1/$n2-->$n3/$n4"]
                adding_intro["$n3/$n4<-->$n1/$n2"]=1
            else 
                adding_intro["$n3/$n4-->$n1/$n2"]=1
            fi   
        fi   
    done 
	mapfile -t adding_intro_sort < <(printf '%s\n' "${!adding_intro[@]}" | LC_ALL=C sort)
	
	((step++))
fi

#====================================================================
# Read D-statistic results and prepare for f-branch analysis
echo "" >&2
echo "================================================="  >&2
echo "Step $step: Reading D-statistic results..." >&2
declare -a TRIPLES_ARRAY
declare -A TRIPLES_RANK  # Store rank of each triple (line number)

if [[ -f "$DSTAT_FILE" ]]; then
	if [[ $(wc -l < "$DSTAT_FILE") -lt 2  ]]; then
		echo "Workflow complete: no significant triples were found in '$DSTAT_FILE'." >&2
		exit 0
	fi

	[[ -n "$LAST_STEP" ]] && echo "Skip explained triples:" >&2
	IFS= read -r header_line < "$DSTAT_FILE"
	read -ra dstat_header <<< "$header_line"
	[[ "${dstat_header[0]}" == "P1" && "${dstat_header[1]}" == "P2" && "${dstat_header[2]}" == "P3" ]] || \
		die "D-statistic file must begin with P1, P2, and P3 columns"
    
    # Read triples data (skip header)
    line_number=1
    while IFS= read -r line; do
        ((line_number++))
        
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
		# Extract first three columns (P1, P2, P3)
		read -r p1 p2 p3 _ <<< "$line"
		[[ -n "$p1" && -n "$p2" && -n "$p3" ]] || die "Malformed D-statistic row at data rank $((line_number - 1))"
        
        # Create triple identifier and store data
        triple_id="${p1},${p2},${p3}"
		if [[ -z ${explained_triples[$triple_id]} ]]; then
        	TRIPLES_ARRAY+=("$triple_id")
        	TRIPLES_RANK["$triple_id"]=$((line_number - 1))  # Rank starts from 1
		else
			echo "$triple_id" >&2
		fi
        
    done < <(tail -n +2 "$DSTAT_FILE")  # Skip header

	# Get anchor triple (highest ranked - first data line)
    if [[ ${#TRIPLES_ARRAY[@]} -gt 0 ]]; then
        ANCHOR_TRIPLE="${TRIPLES_ARRAY[0]}"
        ANCHOR_P1=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f1)
        ANCHOR_P2=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f2)
        ANCHOR_P3=$(echo "$ANCHOR_TRIPLE" | cut -d',' -f3)
		if [[ -n "$LAST_STEP" ]]; then
			echo "" >&2
        	echo "Next triple to consider: $ANCHOR_TRIPLE" >&2
		else
        	echo "First triple to consider: $ANCHOR_TRIPLE" >&2
		fi
    else # must be the conditions with --last_step
		echo "Workflow complete: all significant D-statistic triples are explained by supported introgression events." >&2
		if [[  ${#nonsig_int[@]} -eq 0 ]]; then
			echo "The final model and parameter estimates are in '${LAST_STEP}.txt'." >&2
		else
			echo "" >&2	
			echo "=================================================" >&2
			echo "The final introgression model contains the following introgression events:" >&2
			ctl_con
		fi
		exit 0
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
if [[ ${#CANDIDATE_RESULTS[@]} -eq 0 || "$FBRANCH" == false ]]; then
    # Create default candidate using just the anchor triple
    ANCHOR_TRIPLE_ID="${ANCHOR_P1},${ANCHOR_P2},${ANCHOR_P3}"
    ANCHOR_RANK="${TRIPLES_RANK[$ANCHOR_TRIPLE_ID]}"
    
    # Create single-element subsets for the anchor triple
    P1_SUBSET="$ANCHOR_P1"
    P2_SUBSET="$ANCHOR_P2" 
    P3_SUBSET="$ANCHOR_P3"
   
    CANDIDATE_RESULTS=("SINGLE_ANCHOR:${P1_SUBSET}:${P2_SUBSET}:${P3_SUBSET}:1:${ANCHOR_RANK}")
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
	P1_branch="LCA($best_p1)"
else
	P1_branch=$best_p1
fi
if [[ "$best_p2" == *","* ]]; then
	P2_branch="LCA($best_p2)"
else
	P2_branch=$best_p2
fi
if [[ "$best_p3" == *","* ]]; then
	P3_branch="LCA($best_p3)"
else
	P3_branch=$best_p3
fi

[[ $FBRANCH == "true" ]] && echo "Apply the f_branch rule..." >&2
echo "P1_branch: $P1_branch" >&2
echo "P2_branch: $P2_branch" >&2
echo "P3_branch: $P3_branch" >&2
echo "New introgressions to be tested: ghost->$P1_branch, $P2_branch->$P3_branch $P3_branch->$P2_branch" >&2
((step++))

#============================================================
#generating BPP ctl file
echo "" >&2
echo "=================================================" >&2
echo "Step $step: Generating BPP control file template..." >&2

#construct the backbone tree including ghost lineages
ghost_id=$(echo "$new_tree" | nw_labels - | grep -o -E '(Ghost)[0-9]+' |grep -o '[0-9]\+' | sort -rn |head -1)
inner_id=$(echo "$new_tree" | nw_labels - | grep -o -E '(N)[0-9]+' |grep -o '[0-9]\+' | sort -rn |head -1)
((ghost_id++))
((inner_id++))
newg_pos=$(echo $new_tree | nw_clade - $ANCHOR_P1 $ANCHOR_P2 $ANCHOR_P3 2>/dev/null)
newg_pos=${newg_pos%;}
new_tree=${new_tree/"$newg_pos"/"(Ghost$ghost_id,$newg_pos)N${inner_id}"}
echo "The backbone tree including ghost lineages: $new_tree" >&2
echo "" >&2

#collecting new introgressions
if [[ "$best_p1" == *","* ]]; then
    best_p1_no_comma=${best_p1//,/ }
    P1=$(echo "$new_tree" | nw_clade - $best_p1_no_comma 2>/dev/null | perl -ne 'if (/.*\)\s*([^:;]+)/) {print $1}')
else
    P1="$ANCHOR_P1"
fi
P1_p=$(find_parent_node "$new_tree" "$P1")

if [[ "$best_p2" == *","* ]]; then
    best_p2_no_comma=${best_p2//,/ }
    P2=$(echo "$new_tree" | nw_clade - $best_p2_no_comma 2>/dev/null | perl -ne 'if (/.*\)\s*([^:;]+)/) {print $1}')
else
    P2="$ANCHOR_P2"
fi
P2_p=$(find_parent_node "$new_tree" "$P2")

if [[ "$best_p3" == *","* ]]; then
    best_p3_no_comma=${best_p3//,/ }
    P3=$(echo "$new_tree" | nw_clade - $best_p3_no_comma 2>/dev/null | perl -ne 'if (/.*\)\s*([^:;]+)/) {print $1}')
else
    P3="$ANCHOR_P3"
fi
P3_p=$(find_parent_node "$new_tree" "$P3")
Ghost_p=$(find_parent_node "$new_tree" "Ghost$ghost_id")

adding_intro["$Ghost_p/Ghost$ghost_id-->$P1_p/$P1"]=1
adding_intro["$P2_p/$P2<-->$P3_p/$P3"]=1
adding_intro_sort+=("$Ghost_p/Ghost$ghost_id-->$P1_p/$P1"  "$P2_p/$P2<-->$P3_p/$P3")

echo "All tested introgressions in the present step:" >&2 
ctl_con
LOG_FILE=${PREFIX}.introgression
cat > "$LOG_FILE" << EOF
tree: $new_tree
introgression: 
$merged_intr_log
EOF

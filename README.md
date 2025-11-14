# D-BPP Pipeline: Step-by-Step Workflow

**Yang Y, Pang XX, Ding YM, Zhang BW, Bai WN, Zhang DY. 2025. Synergizing Bayesian and Heuristic Approaches: D-BPP Uncovers Ghost Introgression in Panthera and Thuja. bioRxiv 2025.06.27.662067. doi: https://doi.org/10.1101/2025.06.27.662067**


This document provides a detailed, step-by-step guide for running the D-BPP pipeline, from raw data preparation to the final inference of phylogenetic networks and ghost introgression.

---

## 1. Software Requirements
### a. Dsuite
https://github.com/millanek/Dsuite/tree/master  
Citation: Malinsky, M., Matschiner, M. and Svardal, H. (2021) Dsuite ‐ fast D‐statistics and related admixture evidence from VCF files. Molecular Ecology Resources 21, 584–595. doi: https://doi.org/10.1111/1755-0998.13265

```
git clone https://github.com/millanek/Dsuite.git
cd Dsuite
make
```
### b. BPP
https://github.com/bpp/bpp  
Citation: Flouri T., Jiao X., Rannala B., Yang Z. (2018) Species Tree Inference with BPP using Genomic Sequences and the Multispecies Coalescent. Molecular Biology and Evolution, 35(10):2585-2593. doi:10.1093/molbev/msy147
```
wget https://github.com/bpp/bpp/releases/download/v4.8.4/bpp-4.8.4-linux-x86_64.tar.gz
tar zxvf bpp-4.8.4-linux-x86_64.tar.gz
```
### c. snp-sites  
http://sanger-pathogens.github.io/snp-sites/  
Citation: Page AJ, Taylor B, Delaney AJ, Soares J, Seemann T, Keane JA, Harris SR. 2016. SNP-sites: Rapid efficient extraction of SNPs from multi-fasta alignments. Microb Genom 2:e000056

Install Conda and install the bioconda channels.
```
conda config --add channels conda-forge
conda config --add channels defaults
conda config --add channels r
conda config --add channels bioconda
conda install snp-sites
```

## 2. Data Preparation

### a. Sequence Data

- **Input:** Multi-locus sequence alignments, including both ingroup species and at least one designated outgroup.
- **Format:** Multi-FASTA. Ensure sample names are consistent throughout all analyses.

#### Example: Multi-FASTA Format

```
>Sp1
ATGCTAG...
>Sp2
ATGCCAG...
>Sp3
AATCCTG...
>Sp4
AAGATTC...
……
>Outgroup
...
```
### b. Species Tree Topologies
Provide candidate species trees in Newick format (from prior analyses or literature). 
Example:
```
(((Sp1,Sp2),Sp3),Outgroup);
(((Sp1,Sp3),Sp1),Outgroup);
```
**Auto-generate constrained 5-taxon topologies.**
Generate the three rooted topologies where A/B/C form a clade and D/E are sisters (optionally with an outgroup).
```
# without outgroup
  python get_topos.py --abc A B C --sisters D E

  # with outgroup
  python get_topos.py --abc A B C --sisters D E --outgroup O --outdir results --prefix topo_
```
The command writes three .newick files to --outdir.

## 3. D-statistic (ABBA-BABA)

Use Dsuite or an equivalent tool to identify potential introgression events.

**a. Concatenate multi-locus FASTA (optional)**  
If you have multiple locus-specific FASTA files, you should concatenate them into a single multi-locus alignment.

```
perl concatenate_multi-locus.pl file_list indir output.fasta
# file_list: one FASTA filename per line; indir: directory containing those files
```
**b. Convert FASTA → VCF**

```
snp-sites -v -o output.fasta input.vcf
```

Once the multi-locus FASTA files have been concatenated and converted to VCF format, you can use Dsuite to compute D-statistics for introgression analysis.

**c. build Dsuite commands (auto)**   
Given one or more topology files, generate (i) a triolist for each tree and (ii) a runnable shell script with all Dsuite Dtrios commands:

```
python make_dsuite_cmds.py \
  --vcf output.vcf \
  --imap imap.txt \
  --trees results/*.newick \
  --outdir dsuite_runs \
  --prefix run_ \
  --print
# This creates:
#   dsuite_runs/<tree-basename>.trios.txt
#   dsuite_runs/run_dsuite.sh

```
**d. Run Dsuite**
```
bash dsuite_runs/run_dsuite.sh
# Or: Dsuite Dtrios output.vcf imap.txt --tree=TREE_FILE.nwk -o outprefix <triolist>
```
Dsuite outputs <outprefix>_tree.txt containing D, Z, p, f4-ratio and counts (BBAA/ABBA/BABA).

## 4. Rank signals by 𝐷𝑝 (with significance filtering) 

Compute 𝐷𝑝 =(ABBA−BABA)/(BBAA+ABBA+BABA), filter by |Z| or p, and sort by 𝐷𝑝

```
# Z-filter (default |Z|>=3), keep all rows
python dp_from_Dsuite.py --dir dsuite_runs --glob "*_tree.txt" --outdir dsuite_runs/dp

# p-filter (p<=0.01) and drop non-significant rows
python dp_from_Dsuite.py --dir dsuite_runs --glob "*_tree.txt" \
  --sig p --pmax 0.01 --drop-nonsig --outdir dsuite_runs/dp

```
Outputs *_withDp_sorted.txt, preserving original columns and adding 𝐷𝑝.

## 5. Prepare BPP Inputs
**a. loci.bpp**

Create a list of loci and convert FASTA to BPP format:
```
perl fasta2bpp.pl input_dir loci.list > loci.bpp
```
Each locus block starts with “<nseq> <seqlen>”, followed by lines like locus1^A1 ACTG.....


**b. imap.txt**
Map individuals to species:

```
A1  A
A2  A
B1  B
B2  B
C1  C
C2  C
```
**c. bpp.ctl**
Edit file paths, MSCI model, priors, and MCMC settings, then run:
```
bpp -cfile bpp.ctl

```

### 6. Summarize B<sub>10 
 **a. Compute ​from posterior samples**
 For a table where each phi* column contains posterior samples, compute B<sub>10 with the default cutoff ε=0.01 :
 ```
python cal_b10.py posterior.txt B10_summary.txt
```

### 7. Marginal likelihood
**a. run with BFdriver (thermodynamic integration)**

```
#!/bin/bash
bpp --bfdriver input.ctl --points 16 && \
for i in {1..16}; do sed -i "s/name\.job/-$i.job/g" "input.ctl.$i"; done && \
for i in {1..16}; do nohup bpp -cfile "input.ctl.$i" & done
```

**b. Compute log marginal likelihood**
```
python cal_LNK.py model.betaweights.csv "*.out.*" LNK.txt
# prints the weighted sum and writes results/model_lnK.txt
```

 





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
### d. Set executable paths in your shell  

For convenience, you can add the paths to BPP, Dsuite, and SNP-sites to your shell environment.
Edit your ~/.bashrc and add:
```
# Define Software Paths
export PATH_BPP="/your/path/to/bpp"
export PATH_DSUITE="/your/path/to/dsuite"
export PATH_SNP_SITES="/your/path/to/snp-sites"

# Add to PATH
export PATH="$PATH_BPP:$PATH_DSUITE:$PATH_SNP_SITES:$PATH"
```

Then reload your shell configuration:
```
source ~/.bashrc  
```


## 2. Data Preparation  


### a. Sequence Data

If you have **one FASTA file per locus**, you can prepare input for both Dsuite (VCF) and BPP (PHYLIP) using the steps below.  

**a1. Concatenate multi-locus FASTA and convert FASTA → VCF (for Dsuite)**  

First concatenate all locus-specific FASTA files into a single multi-locus alignment, then convert this alignment to VCF format for use with Dsuite:

```bash
perl concatenate_multi-locus.pl file_list indir output.fasta
# file_list: one FASTA filename per line
# indir:     directory containing those FASTA files
# output:    concatenated multi-locus alignment (output.fasta)

# Convert concatenated FASTA to SNP-only VCF (for Dsuite)
snp-sites -v -o output.vcf output.fasta
```


**a2: Prepare BPP inputs (PHYLIP format)**  

For BPP, multilocus sequence data are stored in a single PHYLIP-style file (`loci.bpp`), organized as one block per locus. 

If you have one FASTA file per locus, you can convert them to a BPP-ready PHYLIP file with:
```
perl fasta2bpp.pl input_dir loci.list > loci.bpp
# input_dir : directory containing per-locus FASTA files
# loci.list : plain-text file with one FASTA filename per line
# loci.bpp  : output multilocus file in PHYLIP-style format for BPP
```

The resulting loci.bpp file is PHYLIP-style and block-structured:
```
<nseq> <seqlen>
locus1^A1   ACTG...
locus1^A2   ACTG...
locus1^B1   ACTG...
...
<nseq> <seqlen>
locus2^A1   ACTG...
locus2^A2   ACTG...
locus2^B1   ACTG...
...
```

- Each locus block starts with a header line:
nseq seqlen (number of sequences, sequence length).

- Followed by nseq lines in standard PHYLIP style:
TAXON_ID<whitespace>SEQUENCE

- TAXON_ID is typically locusID^sampleID (e.g. locus1^A1), as produced by the script.

If you choose to exclude the outgroup from BPP analyses (recommended in many D-BPP use cases), make sure the corresponding outgroup sequences are not included in loci.bpp (either by omitting those samples in the input FASTAs or by removing them after conversion).


### b. Individual-to-Species Mapping 

This file (imap.txt) defines the correspondence between individuals and species for D-statistic (Dsuite) and BPP analysis. To specify the outgroup (which may comprise multiple individuals), use the keyword `Outgroup` as the SPECIES_ID.

Format:
```
<sample_name>TAB<species_name>
```
### c. species tree topology

Provide candidate species trees in Newick format (from prior analyses or literature). 
Example:
```
(((Sp1,Sp2),Sp3),Outgroup);
```

## 3. D-statistic (ABBA-BABA)

Use Dsuite or an equivalent tool to identify potential introgression events.


**Run D-statistic within D-BPP workflow (Dsuite + 𝐷ₚ ranking)**

Use the D-statistic.sh wrapper to: run Dsuite Dtrios for each candidate species tree, compute 𝐷ₚ for each trio, filter trios by significance (Z-score or p-value), and output 𝐷ₚ-sorted result tables.
**Note:** Tree files must be in standard Newick format without any spaces (including in taxon names). If your Newick file contains spaces, please replace them with underscores or remove the spaces before running this script.

```
bash D-statistic.sh \
  --vcf output.vcf \
  --imap imap.txt \
  --treelist treelist.txt \
  --filter p-value \
  --cutoff 0.01 \
  --prefix Sig-Dp

```


**c. bpp.ctl**
Edit file paths, MSCI model, priors, and MCMC settings, then run:
```
bpp -cfile bpp.ctl

```

## 6. Summarize B<sub>10 
 **a. Compute ​from posterior samples**
 For a table where each phi* column contains posterior samples, compute B<sub>10 with the default cutoff ε=0.01 :
 ```
python cal_b10.py posterior.txt B10_summary.txt
```

## 7. Marginal likelihood
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

 





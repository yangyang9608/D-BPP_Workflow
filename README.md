# D-BPP Pipeline: Step-by-Step Workflow

**Yang Y, Pang XX, Ding YM, Zhang BW, Bai WN, Zhang DY. 2025. Synergizing Bayesian and Heuristic Approaches: D-BPP Uncovers Ghost Introgression in Panthera and Thuja. bioRxiv 2025.06.27.662067. doi: https://doi.org/10.1101/2025.06.27.662067**


This document provides a detailed, step-by-step guide for running the D-BPP pipeline, from raw data preparation to the final inference of phylogenetic networks and ghost introgression.

---

## 0. Software Requirements
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
### d. Newick Utilities 
https://github.com/tjunier/newick_utils   
```
git clone https://github.com/tjunier/newick_utils.git
cd newick_utils
./configure
make
```

### d. Set executable paths in your shell  

For convenience, you can add the paths to BPP, Dsuite, and SNP-sites to your shell environment.
Edit your ~/.bashrc and add:
```
# Define Software Paths
export PATH_BPP="/your/path/to/bpp"
export PATH_DSUITE="/your/path/to/dsuite"
export PATH_SNP_SITES="/your/path/to/snp-sites"
export PATH_NEWICK_UTILS="/your/path/to/newick_utils"

# Add to PATH
export PATH="$PATH_BPP:$PATH_DSUITE:$PATH_SNP_SITES:PATH_NEWICK_UTILS:$PATH"
```

Then reload your shell configuration:
```
source ~/.bashrc  
```

## 1. The *D*-statictic within D-BPP workflow  

We provide a shell script that runs Dsuite for each candidate species tree (supplied by the user in a tree-list file) and reports significant triples ranked by *D<sub>p</sub>*.


```
Usage: bash D-step.sh (--fasta_dir <fasta_dir> |--vcf_file <vcf_file>) --imap <imap_file> --treelist <treelist_file> [--prefix <output_prefix>] [--cutoff <value>]

Required parameters (choose one input type):
  --fasta_dir <dir>     Directory containing locus FASTA files
  --vcf_file <file>     VCF file
Other Required parameters:
  --imap <file>         Individual to species mapping file <sample_name>TAB<species_name>
  --treelist <file>     File containing multiple trees (one per line)

Optional parameters:
  --cutoff <value>      Cutoff value for p-value (default: 0.01)
  --prefix <prefix>     Output prefix (path will be created if needed; default: Sig-Dp)

Output:
  For each tree in treelist, generates prefix-Tree*-triples.txt containing
  all significant triples (after Bonferroni correction) sorted by 𝐷𝑝 value in descending order

```


## 2. The BPP analysis within D-BPP workflow  

### a. Prepare for control file
The script can automatically generates first-round BPP control files implementing our three-model comparison of introgression (inflow, outflow, and ghost).  

To date, the current implementation does not yet cover the complete D-BPP workflow, but we will continue to update BPP-step.sh to enable iterative refinement—generating updated BPP control files based on previous BPP results—until all significant triples are fully explained and a final comprehensive introgression model is obtained.


```
Usage: bash BPP-step.sh (--fasta_dir <fasta_directory> | --phylip_file <phylip_file>) --imap <imap_file> --tree <tree_file> --dstat <dstat_file> --prefix <output_prefix>

Required parameters (choose one input type):
  --fasta_dir <dir>     Directory containing locus FASTA files
  --phylip_file <file>  Existing BPP-PHYLIP file

Other required parameters:
  --imap <file>         Individual to species mapping file (tab-delimited)
  --tree <file>         Species tree file
  --dstat <file>        D-statistic results file
  --prefix <prefix>     Output prefix for BPP files

Optional parameters:
  --skip_validation     Skip PHYLIP file format validation (only with --phylip_file)
```
### b. run BPP
```
bpp -cfile bpp.ctl
```

## c. Summarize *B*<sub>10 
 **a. Compute ​from posterior samples**
 For a table where each phi* column contains posterior samples, compute *B*<sub>10</sub> with the default cutoff *ε*=0.01 :
 ```
python cal_b10.py posterior.txt B10_summary.txt
```

## d. Marginal likelihood
**d1. run with BFdriver (thermodynamic integration)**

```
#!/bin/bash
bpp --bfdriver input.ctl --points 16 && \
for i in {1..16}; do sed -i "s/name\.job/-$i.job/g" "input.ctl.$i"; done && \
for i in {1..16}; do nohup bpp -cfile "input.ctl.$i" & done
```

**d2. Compute log marginal likelihood**
```
python cal_marginal_likelihoods.py model.betaweights.csv "*.out.*" LNK.txt
# prints the weighted sum and writes results/model_lnK.txt
```

 





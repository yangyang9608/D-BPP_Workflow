# D-BPP Workflow example data

This directory contains a small synthetic dataset for running D-BPP Workflow from D-statistic screening through first-round MSci model construction.

## Data

- Ingroup species: A, B, C
- Two sequences per ingroup species
- One outgroup sequence (`O1`, mapped to the required species label `Outgroup`)
- 20 aligned loci
- 500 bp per locus
- Candidate species tree: `((A,B),C);`

The data were constructed as a deterministic software example. They are intended to verify
that D-BPP Workflow runs correctly; they are not intended for biological inference or
statistical-power assessment.

For the only ingroup triple, `((A,B),C)`, the designed site-pattern totals are:

- ABBA = 600
- BABA = 200
- BBAA = 200
- expected D = 0.50
- expected Dp = 0.40

## Files

- `loci/` — aligned FASTA loci
- `example.imap` — individual-to-species map
- `example.treelist` — candidate ingroup species tree
- `expected_site_patterns.tsv` — designed site-pattern totals

## 1. Run D-step

From the repository root:

```bash
mkdir -p results/example

bash D-step.sh \
  --fasta_dir examples/loci \
  --imap examples/example.imap \
  --treelist examples/example.treelist \
  --prefix results/example/Sig-D \
  --cutoff 0.01 \
  2>&1 | tee results/example/D-step.log
```

The only ingroup triple is `((A,B),C)`, and it is designed to show a strong excess of
ABBA over BABA.

## 2. Run BPP-step

D-step writes a candidate-tree file and a ranked significant-triple file. Use those outputs
with the same full FASTA loci and the original map:

```bash
TREE=$(find results/example -type f -name '*.tree' | head -n 1)
SIG=$(find results/example -type f -name '*.sig-triples' | head -n 1)

bash BPP-step.sh \
  --fasta_dir examples/loci \
  --imap examples/example.imap \
  --tree "$TREE" \
  --dstat "$SIG" \
  --prefix results/example/round1 \
  2>&1 | tee results/example/BPP-step.log
```

For anchor triple `((A,B),C)`, the first candidate model should contain:

- C -> B
- B -> C
- ghost -> A

Before running BPP, inspect the generated network and control file and adjust the MCMC
settings as appropriate.

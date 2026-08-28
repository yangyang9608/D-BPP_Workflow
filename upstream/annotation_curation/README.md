# Annotation curation

This optional module converts genome assemblies plus protein-coding GFF3 annotations into curated protein sets suitable for downstream orthogroup inference.

It is separated from gene-content tree inference so that users can stop after annotation curation or provide their own curated proteomes to the downstream [`../gene_content_tree/`](../gene_content_tree/) module.

## Dependencies

- Bash 4+
- Python 3.10+
- [AGAT](https://agat.readthedocs.io/)
- [BEDTools](https://bedtools.readthedocs.io/)
- [gffread](https://github.com/gpertea/gffread)
- [SeqKit](https://bioinf.shenwei.me/seqkit/)

## Input manifest

Copy [`config/species.tsv.example`](config/species.tsv.example) and provide one tab-delimited row per species:

```text
species\tgenome_fasta\tannotation_gff3
SpeciesA\t/path/to/SpeciesA.fa\t/path/to/SpeciesA.gff3
SpeciesB\t/path/to/SpeciesB.fa\t/path/to/SpeciesB.gff3
```

Species labels must be unique and should contain only letters, numbers, `_`, `-`, or `.`.

## 1. Curate annotations and extract coding sequences

```bash
./01_curate_annotations.sh \
  --manifest config/species.tsv \
  --out-dir work/01_curated
```

For each species, the script:

- parses and normalizes the GFF3 with AGAT;
- retains the longest protein-coding isoform per gene;
- builds transcript-level CDS spans;
- groups overlapping coding spans with BEDTools;
- retains the transcript with the longest summed CDS length from each overlap component;
- filters the annotation to the selected representatives;
- extracts CDS and peptide FASTA files with gffread; and
- removes coding models whose CDS length is not divisible by three or whose protein contains an internal stop codon.

By default, overlap components are defined on the same chromosome/scaffold regardless of strand. Use `--strand-aware` to cluster overlaps separately by strand.

Key outputs include:

```text
work/01_curated/SpeciesA/SpeciesA.curated.gff3
work/01_curated/SpeciesA/SpeciesA.cds.fa
work/01_curated/SpeciesA/SpeciesA.faa
work/01_curated/SpeciesA/SpeciesA.id_map.tsv
work/01_curated/SpeciesA/SpeciesA.coding_filter_summary.tsv
```

Protein and CDS identifiers are prefixed with the species label (`SpeciesA|...`) to keep identifiers globally unique across proteomes.

## 2. Generate protein-length-filtered datasets

```bash
./02_make_protein_sets.sh \
  --manifest config/species.tsv \
  --curated-dir work/01_curated \
  --out-dir work/02_protein_sets
```

The default thresholds are 0, 50, 100, and 150 amino acids, producing:

```text
work/02_protein_sets/all/
work/02_protein_sets/min50aa/
work/02_protein_sets/min100aa/
work/02_protein_sets/min150aa/
```

The thresholds are configurable, for example:

```bash
./02_make_protein_sets.sh \
  --manifest config/species.tsv \
  --curated-dir work/01_curated \
  --out-dir work/02_protein_sets \
  --thresholds 0,100,150
```

Each resulting directory contains one `.faa` file per species and can be passed directly to the downstream gene-content module.

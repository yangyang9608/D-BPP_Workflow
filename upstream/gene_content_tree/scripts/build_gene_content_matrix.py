#!/usr/bin/env python3
"""Convert OrthoFinder Orthogroups.GeneCount.tsv to binary gene-content matrices."""

import argparse
import csv
from pathlib import Path


def parse_count(value, og, species):
    try:
        x = float(value)
    except ValueError:
        raise SystemExit(f'non-numeric count for {og} / {species}: {value!r}')
    if x < 0 or int(x) != x:
        raise SystemExit(f'invalid gene count for {og} / {species}: {value!r}')
    return int(x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gene-count', required=True, help='OrthoFinder Orthogroups.GeneCount.tsv')
    ap.add_argument('--out-prefix', required=True)
    ap.add_argument('--min-species', type=int, default=1,
                    help='minimum number of species in which an orthogroup must be present')
    ap.add_argument('--keep-universal', action='store_true',
                    help='retain families present in all taxa (not recommended with +ASC)')
    args = ap.parse_args()

    if args.min_species < 1:
        raise SystemExit('--min-species must be >= 1')

    with open(args.gene_count, newline='', encoding='utf-8') as fh:
        reader = csv.DictReader(fh, delimiter='\t')
        if not reader.fieldnames or reader.fieldnames[0] != 'Orthogroup':
            raise SystemExit('expected first column named Orthogroup')
        species = [x for x in reader.fieldnames[1:] if x.lower() != 'total']
        if len(species) < 3:
            raise SystemExit('at least three species columns are required')
        if len(species) != len(set(species)):
            raise SystemExit('duplicate species names in gene-count header')
        bad = [s for s in species if any(c.isspace() for c in s)]
        if bad:
            raise SystemExit(f'species names may not contain whitespace: {bad}')

        kept = []
        dropped_universal = 0
        dropped_min = 0
        for row in reader:
            og = row['Orthogroup']
            bits = []
            for sp in species:
                bits.append(1 if parse_count(row[sp], og, sp) > 0 else 0)
            n_present = sum(bits)
            if n_present < args.min_species:
                dropped_min += 1
                continue
            if not args.keep_universal and n_present == len(species):
                dropped_universal += 1
                continue
            kept.append((og, bits))

    if not kept:
        raise SystemExit('no informative orthogroups remained after filtering')

    prefix = Path(args.out_prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)

    tsv_path = Path(str(prefix) + '.tsv')
    phy_path = Path(str(prefix) + '.phy')
    summary_path = Path(str(prefix) + '.summary.tsv')

    # Species-by-orthogroup table.
    with open(tsv_path, 'w', encoding='utf-8') as out:
        out.write('Species\t' + '\t'.join(og for og, _ in kept) + '\n')
        for i, sp in enumerate(species):
            out.write(sp + '\t' + '\t'.join(str(bits[i]) for _, bits in kept) + '\n')

    with open(phy_path, 'w', encoding='utf-8') as out:
        out.write(f'{len(species)} {len(kept)}\n')
        for i, sp in enumerate(species):
            states = ''.join(str(bits[i]) for _, bits in kept)
            out.write(f'{sp} {states}\n')

    with open(summary_path, 'w', encoding='utf-8') as out:
        out.write('metric\tvalue\n')
        out.write(f'n_species\t{len(species)}\n')
        out.write(f'n_orthogroups_retained\t{len(kept)}\n')
        out.write(f'min_species\t{args.min_species}\n')
        out.write(f'dropped_below_min_species\t{dropped_min}\n')
        out.write(f'dropped_universal\t{dropped_universal}\n')
        out.write(f'keep_universal\t{int(args.keep_universal)}\n')

    print(phy_path)


if __name__ == '__main__':
    main()

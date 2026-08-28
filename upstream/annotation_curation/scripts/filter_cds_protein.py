#!/usr/bin/env python3
"""Filter paired CDS/protein FASTA files for basic coding-model validity."""

import argparse


def read_fasta(path):
    seqs = {}
    order = []
    name = None
    chunks = []
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.rstrip('\n')
            if not line:
                continue
            if line.startswith('>'):
                if name is not None:
                    seqs[name] = ''.join(chunks).replace(' ', '')
                name = line[1:].split()[0]
                if name in seqs or name in order:
                    raise SystemExit(f'duplicate FASTA ID {name!r} in {path}')
                order.append(name)
                chunks = []
            else:
                if name is None:
                    raise SystemExit(f'sequence encountered before FASTA header in {path}')
                chunks.append(line.strip())
        if name is not None:
            seqs[name] = ''.join(chunks).replace(' ', '')
    return seqs, order


def write_fasta(path, records, width=60):
    with open(path, 'w', encoding='utf-8') as out:
        for name, seq in records:
            out.write(f'>{name}\n')
            for i in range(0, len(seq), width):
                out.write(seq[i:i+width] + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cds', required=True)
    ap.add_argument('--protein', required=True)
    ap.add_argument('--out-cds', required=True)
    ap.add_argument('--out-protein', required=True)
    ap.add_argument('--id-map', required=True)
    ap.add_argument('--summary', required=True)
    ap.add_argument('--prefix', default='')
    args = ap.parse_args()

    cds, cds_order = read_fasta(args.cds)
    pep, _ = read_fasta(args.protein)

    kept_cds = []
    kept_pep = []
    rows = []
    counts = {'kept': 0, 'missing_protein': 0, 'cds_not_divisible_by_3': 0,
              'empty_protein': 0, 'internal_stop': 0}

    for old_id in cds_order:
        if old_id not in pep:
            counts['missing_protein'] += 1
            continue
        c = cds[old_id].upper()
        p = pep[old_id].upper()
        if len(c) % 3 != 0:
            counts['cds_not_divisible_by_3'] += 1
            continue
        if not p:
            counts['empty_protein'] += 1
            continue
        if '*' in p[:-1]:
            counts['internal_stop'] += 1
            continue
        if p.endswith('*'):
            p = p[:-1]
        if not p:
            counts['empty_protein'] += 1
            continue
        new_id = f'{args.prefix}|{old_id}' if args.prefix else old_id
        kept_cds.append((new_id, c))
        kept_pep.append((new_id, p))
        rows.append((old_id, new_id))
        counts['kept'] += 1

    write_fasta(args.out_cds, kept_cds)
    write_fasta(args.out_protein, kept_pep)

    with open(args.id_map, 'w', encoding='utf-8') as out:
        out.write('original_id\toutput_id\n')
        for row in rows:
            out.write('\t'.join(row) + '\n')

    with open(args.summary, 'w', encoding='utf-8') as out:
        out.write('category\tcount\n')
        for key in ['kept', 'missing_protein', 'cds_not_divisible_by_3', 'empty_protein', 'internal_stop']:
            out.write(f'{key}\t{counts[key]}\n')

    if not kept_pep:
        raise SystemExit('no valid coding models remained after filtering')


if __name__ == '__main__':
    main()

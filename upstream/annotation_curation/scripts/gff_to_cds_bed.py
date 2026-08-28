#!/usr/bin/env python3
"""Convert transcript CDS spans from GFF3 to BED6.

Output columns: seqid, start0, end, transcript_id, summed_cds_length, strand.
"""

import argparse
import sys
from collections import defaultdict


def parse_attrs(text):
    out = {}
    for item in text.strip().strip(';').split(';'):
        if not item:
            continue
        if '=' in item:
            k, v = item.split('=', 1)
            out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gff', required=True)
    args = ap.parse_args()

    cds = defaultdict(list)
    seqids = {}
    strands = {}

    with open(args.gff, encoding='utf-8') as fh:
        for lineno, line in enumerate(fh, 1):
            if not line.strip() or line.startswith('#'):
                continue
            fields = line.rstrip('\n').split('\t')
            if len(fields) != 9:
                raise SystemExit(f'{args.gff}:{lineno}: expected 9 GFF3 columns')
            seqid, _, feature, start, end, _, strand, _, attr_text = fields
            if feature.lower() != 'cds':
                continue
            attrs = parse_attrs(attr_text)
            parents = attrs.get('Parent', '')
            if not parents:
                continue
            start_i, end_i = int(start), int(end)
            for parent in parents.split(','):
                parent = parent.strip()
                if not parent:
                    continue
                cds[parent].append((start_i, end_i))
                if parent in seqids and seqids[parent] != seqid:
                    raise SystemExit(f'transcript {parent!r} has CDS on multiple seqids')
                if parent in strands and strands[parent] != strand:
                    raise SystemExit(f'transcript {parent!r} has CDS on multiple strands')
                seqids[parent] = seqid
                strands[parent] = strand

    if not cds:
        raise SystemExit('no CDS features with Parent attributes were found')

    rows = []
    for tid, parts in cds.items():
        start = min(x[0] for x in parts)
        end = max(x[1] for x in parts)
        cds_len = sum(e - s + 1 for s, e in parts)
        rows.append((seqids[tid], start - 1, end, tid, cds_len, strands[tid]))

    rows.sort(key=lambda x: (x[0], x[1], x[2], x[3]))
    for row in rows:
        print('\t'.join(map(str, row)))


if __name__ == '__main__':
    main()

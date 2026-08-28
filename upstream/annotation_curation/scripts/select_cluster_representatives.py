#!/usr/bin/env python3
"""Select the longest-CDS transcript from each BEDTools cluster."""

import argparse
from collections import defaultdict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clustered-bed', required=True)
    ap.add_argument('--keep-list', required=True)
    ap.add_argument('--summary', required=True)
    args = ap.parse_args()

    clusters = defaultdict(list)
    with open(args.clustered_bed, encoding='utf-8') as fh:
        for lineno, line in enumerate(fh, 1):
            if not line.strip():
                continue
            f = line.rstrip('\n').split('\t')
            if len(f) < 7:
                raise SystemExit(f'{args.clustered_bed}:{lineno}: expected BED6 plus cluster ID')
            chrom, start, end, tid, cds_len, strand = f[:6]
            cluster = f[-1]
            clusters[cluster].append(
                (int(cds_len), int(end) - int(start), tid, chrom, int(start), int(end), strand)
            )

    selected = []
    summary_rows = []
    for cluster in sorted(clusters, key=lambda x: int(x) if x.isdigit() else x):
        members = clusters[cluster]
        # Longest summed CDS first, then longest genomic span, then lexical ID for reproducibility.
        winner = sorted(members, key=lambda x: (-x[0], -x[1], x[2]))[0]
        selected.append(winner[2])
        summary_rows.append((cluster, len(members), winner[2], winner[0], winner[3], winner[4], winner[5], winner[6]))

    with open(args.keep_list, 'w', encoding='utf-8') as out:
        for tid in selected:
            out.write(tid + '\n')

    with open(args.summary, 'w', encoding='utf-8') as out:
        out.write('cluster_id\tn_members\tselected_transcript\tcds_length\tseqid\tstart0\tend\tstrand\n')
        for row in summary_rows:
            out.write('\t'.join(map(str, row)) + '\n')


if __name__ == '__main__':
    main()

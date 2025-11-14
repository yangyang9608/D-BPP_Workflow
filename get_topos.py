#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate the three rooted 5-taxon species-tree topologies under constraints:
- A, B, C form a clade
- D and E are sisters
Optionally include an outgroup as the sister to the entire ingroup.
Write each topology to a separate Newick file.

Examples:
  # without outgroup
  python get_topos.py --abc A B C --sisters D E

  # with outgroup
  python get_topos.py --abc A B C --sisters D E --outgroup O --outdir results --prefix topo_

Output files (with default names/prefix):
  topo_AB_C_vs_DE[__OG].newick
Each file contains 1 Newick tree ending with ';'
"""

import argparse
import os
import re
from itertools import combinations

ILLEGAL_NEWICK = re.compile(r"[(),:; \t\r\n]")  # disallow characters that break unquoted Newick
ILLEGAL_PATH = re.compile(r"[^A-Za-z0-9._-]+")

def validate_label(label: str) -> None:
    if not label:
        raise ValueError("Empty taxon label is not allowed.")
    if ILLEGAL_NEWICK.search(label):
        raise ValueError(
            f"Taxon label '{label}' contains characters reserved in Newick "
            "(one of () , : ; or whitespace)."
        )

def safe_name(s: str) -> str:
    """Make a filesystem-friendly token from a label."""
    return ILLEGAL_PATH.sub("_", s)

def cherry(x: str, y: str) -> str:
    """Return a canonical cherry (x,y) with lexicographic order."""
    a, b = sorted([x, y])
    return f"({a},{b})"

def main():
    ap = argparse.ArgumentParser(description="Enumerate constrained 5-taxon species trees and write separate Newick files.")
    ap.add_argument("--abc", nargs=3, required=True, metavar=("A","B","C"),
                    help="Three taxa that form a clade (order does not matter).")
    ap.add_argument("--sisters", nargs=2, required=True, metavar=("D","E"),
                    help="Two sister taxa (a fixed cherry).")
    ap.add_argument("--outgroup", default=None,
                    help="Optional outgroup label; if provided, final tree is ((ingroup),OUTGROUP);")
    ap.add_argument("--outdir", default=".", help="Output directory (default: current directory).")
    ap.add_argument("--prefix", default="topo_", help="Filename prefix (default: 'topo_').")
    ap.add_argument("--print", action="store_true", help="Also print written filenames and Newick strings.")
    args = ap.parse_args()

    A, B, C = args.abc
    D, E = args.sisters
    labels = [A, B, C, D, E]

    if args.outgroup:
        labels.append(args.outgroup)

    # Validate uniqueness and characters
    if len(set(labels)) != len(labels):
        raise ValueError("All taxon labels (including outgroup if provided) must be distinct.")
    for lbl in labels:
        validate_label(lbl)

    os.makedirs(args.outdir, exist_ok=True)

    written = []
    for pair in combinations([A, B, C], 2):
        other = next(x for x in [A, B, C] if x not in pair)
        # Build ingroup: (((X,Y),Z),(D,E));
        left = f"({cherry(pair[0], pair[1])},{other})"
        right = cherry(D, E)
        ingroup = f"({left},{right})"

        # Attach outgroup if provided: ((ingroup),OG);
        if args.outgroup:
            newick = f"({ingroup},{args.outgroup});"
        else:
            newick = f"{ingroup};"

        # Filename like topo_AB_C_vs_DE[__OG].newick
        pair_token = safe_name(pair[0]) + safe_name(pair[1])
        other_token = safe_name(other)
        sisters_token = safe_name(D) + safe_name(E)
        og_token = f"__{safe_name(args.outgroup)}" if args.outgroup else ""
        fname = f"{args.prefix}{pair_token}_{other_token}_vs_{sisters_token}{og_token}.newick"
        fpath = os.path.join(args.outdir, fname)

        with open(fpath, "w", encoding="utf-8") as f:
            f.write(newick + "\n")
        written.append((fpath, newick))

    if args.print:
        print("Written files:")
        for fn, nwk in written:
            print(f"  {fn}\t{nwk}")

if __name__ == "__main__":
    main()

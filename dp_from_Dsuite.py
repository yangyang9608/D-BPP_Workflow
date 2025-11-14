#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Compute Dp for Dsuite *_tree.txt files with significance filtering and sort by Dp.
No 'Sig' column is written; Dp is computed only for rows passing the significance filter.
Non-significant rows keep all original columns and have Dp set to 'NA' (or empty if --empty-nonsig).

Expected header (tab- or comma-delimited):
P1  P2  P3  Dstatistic  Z-score  p-value  f4-ratio  BBAA  ABBA  BABA

Dp = (ABBA - BABA) / (BBAA + ABBA + BABA)

Usage examples:
  # single file (Z filter |Z|>=3)
  python dp_from_Dsuite.py --input out_tree.txt

  # directory (p-value filter p<=0.01) and drop non-significant rows
  python dp_from_Dsuite.py --dir ./results --sig p --pmax 0.01 --drop-nonsig --outdir ./dp_sorted

  # write empty string instead of 'NA' for non-significant rows
  python dp_from_Dsuite.py --input out_tree.txt --empty-nonsig
"""
import argparse
import csv
import glob
import math
import os

ABBA_NAMES = ["ABBA"]
BABA_NAMES = ["BABA"]
BBAA_NAMES = ["BBAA"]
Z_NAMES    = ["Z-score", "Zscore", "Z"]
P_NAMES    = ["p-value", "pvalue", "pval", "p"]

def detect_delimiter(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        head = f.readline()
    return "\t" if ("\t" in head and head.count("\t") >= head.count(",")) else ","

def pick_col(header, candidates, required=True):
    if header is None:
        header = []
    lower = {h.lower(): h for h in header}
    for name in candidates:
        key = name.lower()
        if key in lower:
            return lower[key]
    if required:
        raise KeyError(f"Cannot find any of {candidates} in header: {header}")
    return None

def to_float(x):
    try:
        return float(x)
    except Exception:
        return float("nan")

def is_significant(row, mode, zmin, pmax, z_col, p_col):
    if mode == "z":
        if not z_col:
            return False
        z = to_float(row.get(z_col, "nan"))
        return (z == z) and (abs(z) >= zmin)
    if mode == "p":
        if not p_col:
            return False
        p = to_float(row.get(p_col, "nan"))
        return (p == p) and (p <= pmax)
    return True  # mode == "none" -> treat all as significant

def process_file(infile, outdir=None, prefix="", sig_mode="z", zmin=3.0, pmax=0.01,
                 drop_nonsig=False, empty_nonsig=False):
    delim = detect_delimiter(infile)
    with open(infile, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter=delim)
        header = reader.fieldnames or []

        abba_col = pick_col(header, ABBA_NAMES)
        baba_col = pick_col(header, BABA_NAMES)
        bbaa_col = pick_col(header, BBAA_NAMES)
        z_col    = pick_col(header, Z_NAMES, required=(sig_mode == "z"))
        p_col    = pick_col(header, P_NAMES, required=(sig_mode == "p"))

        rows = []
        for row in reader:
            sig = is_significant(row, sig_mode, zmin, pmax, z_col, p_col)
            if not sig and drop_nonsig:
                continue

            abba = to_float(row.get(abba_col, "nan"))
            baba = to_float(row.get(baba_col, "nan"))
            bbaa = to_float(row.get(bbaa_col, "nan"))
            denom = bbaa + abba + baba

            if sig and (denom == denom) and (denom != 0.0):
                dp = (abba - baba) / denom
                row["Dp"] = f"{dp:.6f}"
            else:
                dp = float("nan")
                row["Dp"] = "" if empty_nonsig else "NA"

            rows.append((dp, row))

    # Sort: Dp descending; NaN at the end
    rows.sort(key=lambda t: (-(t[0]) if t[0] == t[0] else math.inf))
    sorted_rows = [r for _, r in rows]

    base = os.path.basename(infile)
    name, ext = os.path.splitext(base)
    outname = f"{prefix}{name}_withDp_sorted{ext or '.txt'}"
    outdir = outdir or os.path.dirname(infile) or "."
    os.makedirs(outdir, exist_ok=True)
    outfile = os.path.join(outdir, outname)

    # Write original columns + Dp (no Sig)
    fieldnames = header[:]
    if "Dp" not in fieldnames:
        fieldnames.append("Dp")

    with open(outfile, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter=delim)
        writer.writeheader()
        for row in sorted_rows:
            writer.writerow(row)

    print(f"[OK] {infile} -> {outfile}  (rows kept: {len(sorted_rows)})")
    return outfile

def main():
    ap = argparse.ArgumentParser(description="Compute and sort Dp for Dsuite *_tree.txt with Z/p filtering (no Sig column).")
    ap.add_argument("--input", nargs="*", help="One or more *_tree.txt files.")
    ap.add_argument("--dir", default=None, help="Directory containing *_tree.txt files.")
    ap.add_argument("--glob", default="*_tree.txt", help="Glob pattern under --dir (default: *_tree.txt).")
    ap.add_argument("--outdir", default=None, help="Output directory (default: alongside inputs).")
    ap.add_argument("--prefix", default="", help="Output filename prefix.")

    ap.add_argument("--sig", choices=["z", "p", "none"], default="z",
                    help="Significance criterion: z (|Z|>=zmin), p (p<=pmax), or none (compute Dp for all).")
    ap.add_argument("--zmin", type=float, default=3.0, help="Z threshold for significance (|Z|>=zmin).")
    ap.add_argument("--pmax", type=float, default=0.01, help="p-value threshold (p<=pmax).")
    ap.add_argument("--drop-nonsig", action="store_true",
                    help="Drop non-significant rows (otherwise keep with Dp=NA or empty).")
    ap.add_argument("--empty-nonsig", action="store_true",
                    help="Write empty string for non-significant Dp instead of 'NA'.")

    args = ap.parse_args()

    files = []
    if args.input:
        for p in args.input:
            if os.path.isdir(p):
                files.extend(glob.glob(os.path.join(p, args.glob)))
            else:
                files.append(p)
    elif args.dir:
        files = glob.glob(os.path.join(args.dir, args.glob))
    else:
        ap.error("Please provide --input files or --dir directory.")

    if not files:
        raise SystemExit("No input files found.")

    for fpath in files:
        process_file(
            fpath,
            outdir=args.outdir,
            prefix=args.prefix,
            sig_mode=args.sig,
            zmin=args.zmin,
            pmax=args.pmax,
            drop_nonsig=args.drop_nonsig,
            empty_nonsig=args.empty_nonsig,
        )

if __name__ == "__main__":
    main()

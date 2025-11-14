#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Automate generation of Dsuite commands for all relevant triplets given a topology.

For each input Newick tree:
  1) Parse the topology (labels must match population names in imap).
  2) Enumerate all C(n,3) taxon triplets and orient each as (P1,P2,P3):
     P1,P2 = the closest pair in the tree; P1 and P2 are sorted lexicographically.
  3) Write a triolist file "<basename>.trios.txt" with lines "P1 P2 P3".
  4) Append a Dsuite command to "run_dsuite.sh":
     Dsuite Dtrios <vcf> <imap> --tree=<treefile> -o <outprefix> <triolist>

Usage:
  python make_dsuite_cmds.py --vcf input.vcf --imap imap.txt --trees topo_AB_C_vs_DE.newick topo_AC_B_vs_DE.newick topo_BC_A_vs_DE.newick --outdir dsuite_runs --prefix run_
  python make_dsuite_cmds.py --vcf input.vcf --imap imap.txt --trees "/path/to/trees/*.newick"  --outdir dsuite_runs --prefix run_ 
"""

import argparse, os, glob, re
from itertools import combinations, chain
from collections import defaultdict, deque

# ---------------- Newick parsing (branch lengths ignored) ---------------- #
TOK_LABEL = re.compile(r"[^(),:;\s]+")  # allowed label token (no spaces or punctuation used by Newick)

class Node:
    __slots__ = ("name", "children", "id")
    def __init__(self, name=None):
        self.name = name
        self.children = []
        self.id = None

def parse_newick(s: str) -> Node:
    """Tiny Newick parser -> root Node. Ignores branch lengths and internal labels."""
    s = s.strip()
    if s.endswith(";"):
        s = s[:-1]

    i = 0
    nid = 0
    def new_id():
        nonlocal nid
        nid += 1
        return nid

    def parse_subtree(idx):
        # subtree can be: (subtrees)label? :branch?  |  leaflabel :branch?
        if idx < len(s) and s[idx] == "(":
            idx += 1  # skip '('
            children = []
            while True:
                child, idx = parse_subtree(idx)
                children.append(child)
                if idx < len(s) and s[idx] == ",":
                    idx += 1
                    continue
                elif idx < len(s) and s[idx] == ")":
                    idx += 1
                    break
                else:
                    raise ValueError(f"Malformed Newick near position {idx}: '{s[max(0,idx-10):idx+10]}'")
            # optional internal label
            m = TOK_LABEL.match(s, idx)
            label = None
            if m:
                label = m.group(0)
                idx = m.end()
            # optional branch length
            if idx < len(s) and s[idx] == ":":
                idx += 1
                # skip branch length token
                mlen = re.match(r"[0-9eE+.\-]+", s[idx:])
                if mlen:
                    idx += mlen.end()
            node = Node(label)
            node.children = children
            node.id = new_id()
            return node, idx
        else:
            m = TOK_LABEL.match(s, idx)
            if not m:
                raise ValueError(f"Expected label at position {idx}")
            label = m.group(0)
            idx = m.end()
            # optional branch length
            if idx < len(s) and s[idx] == ":":
                idx += 1
                mlen = re.match(r"[0-9eE+.\-]+", s[idx:])
                if mlen:
                    idx += mlen.end()
            node = Node(label)
            node.id = new_id()
            return node, idx

    root, j = parse_subtree(i)
    if j != len(s):
        # allow trailing whitespace
        if any(ch.strip() for ch in s[j:]):
            raise ValueError("Extra content after Newick tree.")
    return root

# ------------- Utilities: leaves, adjacency, distances, orientation ------ #
def get_leaves(root: Node):
    leaves = []
    stack = [root]
    while stack:
        x = stack.pop()
        if x.children:
            stack.extend(x.children)
        else:
            leaves.append(x)
    return leaves

def build_adjacency(root: Node):
    adj = defaultdict(list)
    stack = [root]
    nodes = []

    while stack:
        x = stack.pop()
        nodes.append(x)
        for ch in x.children:
            adj[x.id].append(ch.id)
            adj[ch.id].append(x.id)
            stack.append(ch)
    return adj, {n.id: n for n in nodes}

def dist_in_edges(adj, a_id, b_id):
    """Unweighted shortest path length between two node ids."""
    if a_id == b_id:
        return 0
    seen = {a_id}
    dq = deque([(a_id, 0)])
    while dq:
        u, d = dq.popleft()
        for v in adj[u]:
            if v == b_id:
                return d + 1
            if v not in seen:
                seen.add(v)
                dq.append((v, d + 1))
    raise RuntimeError("Nodes not connected")

def orient_triple_by_tree(root: Node, a: str, b: str, c: str):
    """Return (P1,P2,P3) where P1,P2 is the closest pair; P1,P2 sorted lexicographically."""
    adj, idmap = build_adjacency(root)
    # map labels -> ids
    labels = {n.name: n.id for n in get_leaves(root)}
    try:
        ia, ib, ic = labels[a], labels[b], labels[c]
    except KeyError as e:
        raise ValueError(f"Leaf '{e.args[0]}' not found in tree leaves {sorted(labels)}")

    dab = dist_in_edges(adj, ia, ib)
    dac = dist_in_edges(adj, ia, ic)
    dbc = dist_in_edges(adj, ib, ic)

    # choose minimal distance pair
    pairs = [("AB", dab), ("AC", dac), ("BC", dbc)]
    pair, _ = min(pairs, key=lambda x: x[1])
    if pair == "AB":
        p1, p2, p3 = a, b, c
    elif pair == "AC":
        p1, p2, p3 = a, c, b
    else:
        p1, p2, p3 = b, c, a

    # normalize P1,P2 order
    if p2 < p1:
        p1, p2 = p2, p1
    return p1, p2, p3

# --------------------------------- Main ---------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Generate Dsuite commands for all relevant triplets based on topology.")
    ap.add_argument("--vcf", required=True, help="Input VCF file.")
    ap.add_argument("--imap", required=True, help="Population map (imap) file.")
    ap.add_argument("--trees", nargs="+", required=True, help="One or more Newick topology files (e.g., *.newick).")
    ap.add_argument("--outdir", default="dsuite_runs", help="Directory to write triolists and run script.")
    ap.add_argument("--prefix", default="run_", help="Output prefix used in -o for each topology.")
    ap.add_argument("--print", action="store_true", help="Also print the generated commands.")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    run_sh_path = os.path.join(args.outdir, "run_dsuite.sh")
    with open(run_sh_path, "w", encoding="utf-8") as runf:
        runf.write("#!/usr/bin/env bash\nset -euo pipefail\n\n")

        for tree_path in chain.from_iterable(glob.glob(p) if any(ch in p for ch in "*?[]") else [p] for p in args.trees):
            with open(tree_path, "r", encoding="utf-8") as tf:
                newick = tf.read().strip()
            root = parse_newick(newick)

            leaves = sorted(n.name for n in get_leaves(root))
            if len(set(leaves)) < 3:
                raise ValueError(f"Tree '{tree_path}' has fewer than 3 leaves.")
            # enumerate & orient all 3-sets
            trios = []
            for a, b, c in combinations(leaves, 3):
                p1, p2, p3 = orient_triple_by_tree(root, a, b, c)
                trios.append((p1, p2, p3))

            # write triolist
            base = os.path.splitext(os.path.basename(tree_path))[0]
            triolist_path = os.path.join(args.outdir, f"{base}.trios.txt")
            with open(triolist_path, "w", encoding="utf-8") as tri:
                for p1, p2, p3 in trios:
                    tri.write(f"{p1} {p2} {p3}\n")

            # dsuite command
            outprefix = args.prefix + base
            cmd = f"Dsuite Dtrios {args.vcf} {args.imap} --tree={tree_path} -o {os.path.join(args.outdir, outprefix)} {triolist_path}"
            runf.write(cmd + "\n")
            if args.print:
                print(cmd)

    # make script executable (best-effort on non-Windows)
    try:
        os.chmod(run_sh_path, 0o755)
    except Exception:
        pass
    print(f"Wrote triolists and commands to: {args.outdir}\n  - run script: {run_sh_path}")

if __name__ == "__main__":
    main()

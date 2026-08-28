# Contributing

Bug reports and focused pull requests are welcome. Please include the command used, relevant input-format details, the complete error message, and the versions of the external programs involved. For core D-BPP issues this includes BPP, Dsuite, Newick Utilities, snp-sites, Bash, and Python; for optional upstream-workflow issues also report AGAT, BEDTools, gffread, SeqKit, OrthoFinder, and IQ-TREE versions as applicable.

Before opening a pull request, run:

```bash
bash -n D-step.sh BPP-step.sh upstream/annotation_curation/*.sh upstream/gene_content_tree/*.sh
python3 -m py_compile cal_b10.py cal_marginal_likelihoods.py upstream/annotation_curation/scripts/*.py upstream/gene_content_tree/scripts/*.py
python3 -m unittest discover -s tests -v
```

Changes to model construction or statistical decision rules should include a minimal regression test and a clear explanation of the expected biological interpretation. Changes to the optional upstream modules should preserve the separation between annotation curation, gene-content species-tree construction, and core D-BPP network inference. Manuscript-specific robustness analyses should not be added to the general-purpose workflow.

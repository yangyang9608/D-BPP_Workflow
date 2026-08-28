# Contributing

Bug reports and focused pull requests are welcome. Please include the command used, relevant input-format details, the complete error message, and software versions for BPP, Dsuite, Newick Utilities, snp-sites, Bash, and Python.

Before opening a pull request, run:

```bash
bash -n D-step.sh BPP-step.sh
python3 -m py_compile cal_b10.py cal_marginal_likelihoods.py
python3 -m unittest discover -s tests -v
```

Changes to model construction or statistical decision rules should include a minimal regression test and a clear explanation of the expected biological interpretation.

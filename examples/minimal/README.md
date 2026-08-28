# Minimal synthetic example

These files provide a compact but non-trivial input example for checking D-BPP input formats and first-round BPP control-file generation. The alignment is **synthetic** and is not intended for biological inference or method validation.

The example contains:

- three ingroup species (`A`, `B`, and `C`) with the species tree `((A,B),C)`;
- two sampled individuals per species;
- five independent loci;
- 500 bp per locus (2.5 kb per individual in total); and
- one synthetic significant D-statistic triple used only to exercise the workflow.

With BPP and Newick Utilities in `PATH`, generate a first-round control file with:

```bash
../../BPP-step.sh \
  --phylip_file Test.phy \
  --imap Test.imap \
  --tree Test.tree \
  --dstat Test.sig-triples \
  --prefix output/round1
```

The generated control file should report `nloci = 5` and two sampled individuals for each of the three ingroup species.

The repository test suite in `tests/` deliberately uses much smaller synthetic fixtures and mocked external executables. Those fixtures are kept minimal because they test software logic rather than biological realism. Full datasets associated with the published D-BPP analyses are archived on [Dryad](https://doi.org/10.5061/dryad.47d7wm3sr); they are kept outside this repository because the sequence and MCMC files are substantially larger than this example.

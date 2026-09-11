# D-BPP Workflow v1.2 release checklist

Use this checklist before creating the GitHub tag and Zenodo archive for the Bioinformatics submission.

## 1. Core behavior

- [ ] `D-step.sh` default adjusted-P cutoff is `0.01`.
- [ ] `BPP-step.sh` default `epsilon` is `0.01` and `--eps` remains configurable.
- [ ] `BPP-step.sh` default B10 cutoff is `100` and `--b10_cutoff` remains configurable.
- [ ] If `phiprior` is changed from `1 1`, supply `--prior_mass Pr(phi<epsilon)` in continuation rounds.
- [ ] `cal_b10.py` reports both `epsilon=0.01` and `epsilon=0.001` by default.
- [ ] `--fbranch`, explained-triple pruning and stopping behavior match the manuscript and Figure 1.
- [ ] A triple with no newly supported event is marked as tested and the workflow continues to the next remaining triple; the next candidate model retains all reticulations that remain supported after the preceding BPP evaluation, and only an empty candidate queue terminates iteration.

## 2. Marginal likelihood

For each candidate species tree, finish the complete D-BPP iteration first and obtain its final supported network. Only then perform marginal-likelihood comparison among the resulting final networks.

- [ ] Use the same sequence data across compared final networks.
- [ ] Use consistent priors for parameters shared across compared models.
- [ ] Run each final network in its own working directory.
- [ ] Record the number of Gaussian-quadrature points (16 by default in the documentation).
- [ ] Confirm that `summarize` reports a complete integration-point set with no duplicates.
- [ ] Keep `marginal_likelihood_run/` (logs/manifests) and `marginal_likelihood_results/` (numerical summaries) with the analysis record.

## 3. Installation and provenance

- [ ] Create the Conda environment from `environment.yml`.
- [ ] Run the **default** `bash scripts/install_external.sh` on a clean Linux x86_64 environment; do not use `--latest` or version overrides for the release acceptance record.
- [ ] Run `bash scripts/check_dependencies.sh`.
- [ ] Verify and record BPP 4.8.7 (`bpp --version`).
- [ ] Verify Dsuite 0.5 r58 at pinned commit `a547f99599d763c1760548191ea3f62cc58e8ac3`.
- [ ] Run `DBPP_VERSION=v1.2 bash scripts/record_versions.sh` and retain `software_versions.tsv`; confirm `External_dependency_mode` is `release-pinned`.
- [ ] Optionally run `bash scripts/install_external.sh --latest` in a separate disposable environment as a forward-compatibility test; do not substitute this for the pinned release acceptance test.

## 4. Tests

From the repository root:

```bash
for f in D-step.sh BPP-step.sh scripts/*.sh upstream/annotation_curation/*.sh upstream/gene_content_tree/*.sh; do
  bash -n "$f"
done
python3 -m py_compile cal_b10.py cal_marginal_likelihoods.py upstream/annotation_curation/scripts/*.py upstream/gene_content_tree/scripts/*.py
python3 -m unittest discover -s tests -v
```

The current v1.2 release candidate passes 36 automated tests in the release audit. Re-run the suite after any further code change.

## 5. Release metadata

- [ ] `CITATION.cff` says version `1.2`.
- [ ] `CHANGELOG.md` contains the v1.2 entry.
- [ ] README describes v1.2 behavior and does not claim a v1.2 version-specific DOI before Zenodo creates it.
- [ ] Create GitHub tag `v1.2` and release title `D-BPP Workflow v1.2`.
- [ ] Let Zenodo archive the GitHub release.
- [ ] Copy the new **version-specific v1.2 DOI** into the Bioinformatics manuscript.
- [ ] Update the README citation block with the new v1.2 DOI if desired after archival.

## 6. Manuscript consistency

Before submission, verify the manuscript states:

- default adjusted P cutoff: `0.01`;
- default `epsilon`: `0.01`, user-configurable;
- default B10 cutoff: `100`, user-configurable;
- changed phi priors require the corresponding prior interval probability;
- the standalone B10 utility additionally reports `epsilon=0.001` as a sensitivity value;
- marginal likelihoods compare **final supported networks** obtained independently under alternative candidate species trees, not incomplete intermediate networks;
- D-BPP does not reduce the computational cost of an individual BPP MCMC run.

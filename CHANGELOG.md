# Changelog

All notable changes to D-BPP Workflow will be documented in this file.

## Unreleased

### Added

- Enabled automatic Zenodo archival for GitHub releases.
- Added the Zenodo concept DOI badge and GitHub Release badge to the README.
- Added explicit software citation guidance for both the v1.0.1 version DOI and the all-versions concept DOI.

### Changed

- Updated `CITATION.cff` so that GitHub's repository citation metadata identify D-BPP Workflow v1.0.1 using its version-specific Zenodo DOI.
- Kept the associated *Systematic Biology* methods article as a separate citation in the README.
## [1.0.1] - 2026-08-28

This is the first formally versioned GitHub release of the hardened D-BPP Workflow.

### Added

- Automated tests for B₁₀ calculation, marginal-likelihood integration, FASTA concatenation, D-step filtering, BPP control-file generation, and iterative stopping behavior.
- GitHub Actions continuous integration for Python 3.10 and 3.12.
- A synthetic minimal example containing five 500-bp loci with two sampled individuals per ingroup species.
- MIT license, citation metadata, contributing guidelines, and release changelog.

### Fixed

- Accept the documented `--eps` option in `BPP-step.sh`; retain `--esp` as a deprecated alias.
- Preserve a populated `BPP.imap` during follow-up rounds.
- Generate the BPP `phase` vector only after the complete species count is known.
- Prevent FASTA concatenation from inserting `grep` group separators into sequences.
- Check the actual exit status of `snp-sites`, VCF conversion, and BPP MSCI-model generation.
- Use the documented BPP `--msci-create` option.
- Match current BPP MCMC headers such as `phi:12<-6:Z2<-Z1` to the symbolic event labels stored by the workflow.
- Return success for normal workflow stopping conditions.
- Match thermodynamic-integration beta values with a numerical tolerance and reject incomplete quadrature sets.
- Keep the workflow and standalone B₁₀ utility default epsilon synchronized at `0.001`.

### Changed

- Strengthened input validation and error messages.
- Made species and retained-introgression ordering deterministic.
- Reworked the README around installation, quick-start commands, outputs, interpretation, and reproducibility.
- Expanded and clarified the public minimal example while keeping unit-test fixtures deliberately small for fast CI execution.
- Updated worked README examples to explicitly use `--eps 0.01` (and `--epsilon 0.01` for the standalone utility) without changing the software default of `0.001`.
- Improved the README workflow diagram and standardized mathematical notation, including *D*-statistic, *P* values, Dₚ, ϕ, ε, and B₁₀.

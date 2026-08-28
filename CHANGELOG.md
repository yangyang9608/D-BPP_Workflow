# Changelog

All notable changes to D-BPP Workflow will be documented in this file.

## Unreleased

## [1.1.0] - 2026-08-28

### Added

- Added an optional `upstream/` workflow for constructing candidate species trees before core D-BPP analysis.
- Added a dedicated `upstream/annotation_curation/` module for AGAT-based GFF3 parsing/repair and longest-isoform retention, BEDTools-based overlap clustering, gffread CDS/protein extraction, coding-model validation, and globally unique sequence identifiers.
- Added configurable minimum protein-length datasets (default: 0, 50, 100, and 150 amino acids).
- Added a separate `upstream/gene_content_tree/` module for independent OrthoFinder runs, binary gene-family presence–absence matrix construction and IQ-TREE species-tree inference under `MK+R+FO+ASC` with standard nonparametric bootstrapping.
- Added synthetic upstream examples and three regression tests for matrix conversion, CDS/protein validation, and overlap-representative selection.
- Enabled automatic Zenodo archival for GitHub releases and added Release/DOI badges plus software citation guidance.

### Changed

- Separated annotation preprocessing from gene-content phylogenetic inference so that the two upstream modules can be used or replaced independently.
- Expanded the top-level workflow overview to distinguish optional upstream species-tree construction from the core D-step/BPP-step workflow.
- Extended CI syntax/compile checks and unit tests to the optional upstream modules; the full suite now contains 14 tests.
- Updated repository citation metadata for the v1.1.0 release candidate; the version-specific Zenodo DOI will be added after Zenodo archives the release.
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

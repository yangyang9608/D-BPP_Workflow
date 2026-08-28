# Changelog

All notable changes to D-BPP Workflow will be documented in this file.

## Unreleased

### Example data
- Expanded the minimal synthetic example to five 500-bp loci with two individuals per ingroup species, while keeping the unit-test fixtures deliberately small.

### Added

- Automated tests for B10 calculation, marginal-likelihood integration, FASTA concatenation, D-step filtering, BPP control-file generation, and iterative stopping behavior.
- GitHub Actions continuous integration for Python 3.10 and 3.12.
- MIT license and citation metadata.

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
- Use the same default epsilon (`0.001`) in the workflow and standalone B10 utility.

### Changed

- Strengthened input validation and error messages.
- Made species and retained-introgression ordering deterministic.
- Reworked the README around installation, quick-start commands, outputs, interpretation, and reproducibility.

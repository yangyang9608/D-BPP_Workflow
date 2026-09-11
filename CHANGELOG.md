# Changelog

All notable changes to D-BPP Workflow will be documented in this file.

## [1.2] - 2026-09-11
### Added

- Added `environment.yml` and `INSTALL.md` for reproducible core installation.
- Added a compact 20-locus synthetic example with three ingroup species and one outgroup for running D-statistic screening and first-round MSci model construction.
- Added `scripts/check_dependencies.sh` and `scripts/record_versions.sh` for dependency verification and provenance records.
- Added `scripts/install_external.sh` for one-command installation of the release-pinned BPP 4.8.7 and Dsuite build inside the active Conda environment. The installer also supports explicit `BPP_VERSION` / `DSUITE_COMMIT` overrides and a `--latest` compatibility-testing mode while preserving pinned v1.2 defaults.
- Added `--prior_mass` to `BPP-step.sh`, allowing the Savage-Dickey numerator `Pr(phi < epsilon)` to be supplied explicitly when the phi prior is changed from `Uniform(0,1)`.
- Expanded `cal_b10.py` to report B10 at both `epsilon = 0.01` and `epsilon = 0.001` by default, with compact and detailed output tables.
- Expanded `cal_marginal_likelihoods.py` with `prepare`, `run`, `summarize`, and `compare` subcommands that separate execution logs/manifests from numerical results and support comparison of final networks.

### Changed

- Changed the default B10 interval in `BPP-step.sh` from `epsilon = 0.001` to `epsilon = 0.01`; `--eps` remains user-configurable.
- Kept the default B10 retention cutoff at 100 and documented it as user-configurable.
- Updated the README to describe the joint candidate MSci model, iterative state transfer, final-network comparison, and the v1.2 post-processing interfaces.
- Marginal-likelihood parsing now accepts both current comma-delimited beta-weight files and older whitespace-delimited beta/weight files.
- Expanded automated tests to cover the two default epsilon values, custom prior masses, marginal-likelihood run records, result summaries, model comparison, and non-Uniform phi-prior safeguards.

### Compatibility

- Retained the deprecated `--esp` alias for `--eps`.
- Retained the legacy three-positional-argument syntax of `cal_marginal_likelihoods.py` for existing analyses.

### Fixed

- Fixed FASTA concatenation in `D-step.sh` so sequence identifiers are consistently parsed as the first whitespace-delimited header token; descriptive FASTA headers no longer produce empty concatenated sequences.
- Added strict one-to-one validation between introgression events and BPP posterior `phi` columns, together with row-width and `phi` range checks before B10 filtering.
- Corrected iterative stopping behavior: a triple whose three newly introduced events all fail the B10 cutoff is now recorded as individually tested and removed from the queue, while the workflow continues to the next highest-ranked remaining triple. Round-specific `*.triple-state.tsv` files track `candidate`, `pending`, `explained`, and `tested` states; the workflow stops only when the candidate queue is empty.
- Clarified and regression-tested cumulative-network transfer between rounds: each new candidate model carries forward every reticulation that remains supported after the preceding BPP evaluation, including when the immediately preceding triple yields no newly supported event.
- Moved ancestral-branch subset enumeration behind `--fbranch`, avoiding unnecessary combinatorial candidate generation in the default workflow.
- Corrected CI and documentation shell-syntax commands to run `bash -n` separately on every shell script.
- Fixed reduced final-model construction after unsupported ghost introgression events: unary internal nodes left by `nw_prune` are now collapsed before `bpp --msci-create`, preventing invalid reduced trees such as `(((A,B)N1,C)N2)N3;`.
- Updated completed-workflow handling so the reduced supported network is written as `final.msci`, `final.ctl`, and `final.introgression` rather than being mislabeled as another numbered round.
- Updated `D-step.sh` to identify the appended `Dp` column dynamically before sorting significant triples, so current Dsuite output with additional clustering columns is handled correctly.
- Updated marginal-likelihood summarization to read the BPP screen logs recorded in `run_manifest.tsv` by default, matching where BPP 4.8.7 reports `BFbeta` and `E_b(lnf(X))`; explicit output globs remain supported.
- Standardized installation and release documentation on BPP 4.8.7 and added a version warning to the dependency check.
- Expanded `environment.yml` to include Bash, Perl and the Git/C++ build toolchain required for a clean-server installation.
- Froze the v1.2 Dsuite dependency at version 0.5 r58, Git commit `a547f99599d763c1760548191ea3f62cc58e8ac3`, based on the clean CentOS 8 acceptance environment.
- Updated version recording to obtain the Newick Utilities version from Conda metadata because `nw_prune` does not implement a `--version` option.
- Added external-install metadata so dependency checks and `software_versions.tsv` distinguish the exact `release-pinned` v1.2 environment from user-selected `custom` and unpinned `latest` compatibility-test installations.

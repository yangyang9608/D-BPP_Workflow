# Reproducible installation for D-BPP Workflow

D-BPP Workflow v1.2 uses a two-layer installation strategy: the Conda environment provides the shell/Python runtime and build tools, while an installer script retrieves BPP and Dsuite into the active environment.

The **release-pinned v1.2 environment** is documented and acceptance-tested on Linux x86_64 with **BPP 4.8.7** and **Dsuite 0.5 r58 at Git commit `a547f99599d763c1760548191ea3f62cc58e8ac3`**. This pinned configuration is the default because it provides a stable target for software reproduction. The installer can also install explicitly selected or current upstream versions for compatibility testing without changing the v1.2 defaults.

## 1. Create the D-BPP environment

From the repository root:

```bash
conda env create -f environment.yml
conda activate dbpp
```

`environment.yml` installs Bash >=4.4, Python 3.10, Perl, SNP-sites 2.5.1, Newick Utilities 1.6, Git, Make, a C++ compiler, zlib, wget, and tar.

> **macOS note.** Apple ships `/bin/bash` 3.2, whereas D-BPP requires Bash >=4. Activating the Conda environment supplies a suitable Bash. The automated external-program installer described below is currently configured for Linux binary installation; users on unsupported platforms should install BPP and Dsuite manually and then run the dependency check.

## 2. Install BPP and Dsuite

### Recommended: reproduce the v1.2 external environment

With the `dbpp` environment active, run:

```bash
bash scripts/install_external.sh
```

With no overrides, the installer:

- downloads the official BPP 4.8.7 Linux binary for the detected supported architecture;
- clones Dsuite and checks out commit `a547f99599d763c1760548191ea3f62cc58e8ac3`;
- compiles Dsuite with the Conda C++ toolchain;
- installs both programs under `$CONDA_PREFIX/opt/dbpp-external/`;
- links `bpp` and `Dsuite` into `$CONDA_PREFIX/bin/`;
- writes `$CONDA_PREFIX/opt/dbpp-external/install_metadata.tsv` describing the selected installation mode and exact targets.

The install location is environment-specific and does not modify system directories.

### Install explicitly selected external versions

A newer or alternative BPP release can be tested without editing the installer:

```bash
BPP_VERSION=4.9.0 bash scripts/install_external.sh
```

A specific Dsuite revision can likewise be selected:

```bash
DSUITE_COMMIT=<git-commit> bash scripts/install_external.sh
```

Both may be selected together:

```bash
BPP_VERSION=<version> \
DSUITE_COMMIT=<git-commit> \
bash scripts/install_external.sh
```

These runs are recorded as `custom` external-dependency installations. After changing external versions, rerun the dependency check and bundled tests before production analyses.

### Compatibility test against current upstream versions

To query GitHub at installation time and install the latest BPP release together with the current Dsuite default-branch HEAD:

```bash
bash scripts/install_external.sh --latest
```

This mode is deliberately not the default. It is recorded as `latest` and emits a warning because future BPP releases or Dsuite commits may change file formats, command-line behavior, model construction, or post-processing output. Use `--latest` to test forward compatibility, not to claim exact reproduction of D-BPP Workflow v1.2.

`--latest` cannot be combined with `BPP_VERSION` or `DSUITE_COMMIT` overrides. Run `bash scripts/install_external.sh --help` for the supported modes.

## 3. Verify the installation

Run:

```bash
bash scripts/check_dependencies.sh
```

A complete runtime installation should report `[OK]` for Bash, Python, Perl, SNP-sites, the required Newick Utilities commands, Dsuite, and BPP. The dependency checker reads the installer metadata when available, so custom or `--latest` installations are checked against the versions that were actually requested. It also warns when the active external-dependency mode is not the exact `release-pinned` v1.2 configuration.

For a local source-code test that does not require BPP or Dsuite, use:

```bash
bash scripts/check_dependencies.sh --tests-only
python -m unittest discover -s tests -v
```

The shell-workflow tests use mock external executables but still require Bash >=4.

## 4. Record the software environment

For a release or reproducibility record:

```bash
DBPP_VERSION=v1.2 bash scripts/record_versions.sh software_versions.tsv
cat software_versions.tsv
```

The table records the D-BPP version, external-dependency installation mode, executable paths, installed Bash, Python, Perl, SNP-sites, Newick Utilities, Dsuite and BPP versions, and the exact Dsuite Git commit. For the Bioinformatics v1.2 release record, the external-dependency mode should be `release-pinned`.

## 5. Manual external installation

If `scripts/install_external.sh` is not suitable for the operating system, architecture, or site policy, install BPP and Dsuite manually and place both executables on `PATH`. For analyses intended to reproduce the v1.2 release environment, use:

- BPP 4.8.7;
- Dsuite commit `a547f99599d763c1760548191ea3f62cc58e8ac3`.

Then run `bash scripts/check_dependencies.sh` and `bash scripts/record_versions.sh` to verify and record the environment.

## 6. Release practice

Before creating the GitHub v1.2 tag and Zenodo archive, use the default release-pinned installer, rerun the automated tests, and perform a clean Linux end-to-end smoke test. `--latest` or custom-version runs are useful compatibility checks but do not replace the pinned acceptance test used for the software release. Archive the version-specific Zenodo DOI in the Bioinformatics manuscript together with the v1.2 software citation.

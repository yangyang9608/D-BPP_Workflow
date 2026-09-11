#!/usr/bin/env bash
set -euo pipefail

PINNED_BPP_VERSION="4.8.7"
PINNED_DSUITE_COMMIT="a547f99599d763c1760548191ea3f62cc58e8ac3"
EXPECTED_BPP_VERSION="${DBPP_EXPECTED_BPP_VERSION:-$PINNED_BPP_VERSION}"
EXPECTED_DSUITE_COMMIT="${DBPP_EXPECTED_DSUITE_COMMIT:-$PINNED_DSUITE_COMMIT}"
INSTALL_MODE="${DBPP_EXTERNAL_INSTALL_MODE:-release-pinned}"

metadata_value() {
  local file="$1"
  local key="$2"
  awk -F '\t' -v key="$key" '$1 == key {print $2; exit}' "$file" 2>/dev/null || true
}

METADATA_FILE=""
if [[ -n "${CONDA_PREFIX:-}" ]]; then
  candidate="$CONDA_PREFIX/opt/dbpp-external/install_metadata.tsv"
  if [[ -f "$candidate" ]]; then
    METADATA_FILE="$candidate"
    metadata_bpp=$(metadata_value "$candidate" bpp_version)
    metadata_dsuite=$(metadata_value "$candidate" dsuite_commit)
    metadata_mode=$(metadata_value "$candidate" install_mode)
    [[ -n "$metadata_bpp" && -z "${DBPP_EXPECTED_BPP_VERSION:-}" ]] && EXPECTED_BPP_VERSION="$metadata_bpp"
    [[ -n "$metadata_dsuite" && -z "${DBPP_EXPECTED_DSUITE_COMMIT:-}" ]] && EXPECTED_DSUITE_COMMIT="$metadata_dsuite"
    [[ -n "$metadata_mode" && -z "${DBPP_EXTERNAL_INSTALL_MODE:-}" ]] && INSTALL_MODE="$metadata_mode"
  fi
fi

mode="runtime"
if [[ "${1:-}" == "--tests-only" ]]; then
  mode="tests"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: bash scripts/check_dependencies.sh [--tests-only]" >&2
  exit 2
fi

fail=0
check_cmd() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "[OK]   %-20s %s\n" "$label" "$(command -v "$cmd")"
  else
    printf "[MISS] %-20s not found in PATH\n" "$label"
    fail=1
  fi
}

check_bash_version() {
  if ! command -v bash >/dev/null 2>&1; then
    printf "[MISS] %-20s not found in PATH\n" "Bash >=4"
    fail=1
    return
  fi
  local version major path
  version=$(bash -c 'printf "%s" "$BASH_VERSION"')
  major=${version%%.*}
  path=$(command -v bash)
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 4 )); then
    printf "[OK]   %-20s %s (version %s)\n" "Bash >=4" "$path" "$version"
  else
    printf "[OLD]  %-20s %s (version %s; Bash >=4 is required)\n" "Bash >=4" "$path" "$version"
    fail=1
  fi
}

check_bash_version
check_cmd "Python" python
check_cmd "Perl" perl

if [[ "$mode" == "runtime" ]]; then
  check_cmd "SNP-sites" snp-sites
  check_cmd "Newick: nw_display" nw_display
  check_cmd "Newick: nw_clade" nw_clade
  check_cmd "Newick: nw_labels" nw_labels
  check_cmd "Newick: nw_prune" nw_prune
  check_cmd "Dsuite" Dsuite
  check_cmd "BPP" bpp
fi

echo
if command -v bash >/dev/null 2>&1; then bash --version 2>/dev/null | head -n 1 || true; fi
if command -v python >/dev/null 2>&1; then python --version 2>&1 || true; fi
if command -v perl >/dev/null 2>&1; then perl -v 2>/dev/null | sed -n '2p' || true; fi
if [[ "$mode" == "runtime" ]]; then
  if command -v snp-sites >/dev/null 2>&1; then snp-sites -V 2>&1 | head -n 1 || true; fi
  if command -v Dsuite >/dev/null 2>&1; then Dsuite 2>&1 | head -n 2 || true; fi
  if command -v bpp >/dev/null 2>&1; then bpp --version 2>&1 | head -n 3 || true; fi

  echo
  printf "External dependency mode: %s\n" "$INSTALL_MODE"
  [[ -n "$METADATA_FILE" ]] && printf "Installation metadata:    %s\n" "$METADATA_FILE"
  if [[ "$INSTALL_MODE" != "release-pinned" ]]; then
    printf "[WARN] %-20s %s mode is not the exact v1.2 release-pinned environment\n" "Reproducibility mode" "$INSTALL_MODE" >&2
  fi

  if command -v bpp >/dev/null 2>&1; then
    bpp_version_text=$(bpp --version 2>&1 | head -n 3 || true)
    if grep -Fq "$EXPECTED_BPP_VERSION" <<< "$bpp_version_text"; then
      printf "[OK]   %-20s %s\n" "BPP target version" "$EXPECTED_BPP_VERSION"
    else
      printf "[WARN] %-20s expected %s\n" "BPP target version" "$EXPECTED_BPP_VERSION" >&2
    fi
  fi

  if command -v Dsuite >/dev/null 2>&1; then
    dsuite_path=$(command -v Dsuite)
    dsuite_real=$(readlink -f "$dsuite_path" 2>/dev/null || printf '%s' "$dsuite_path")
    dsuite_repo=$(dirname "$(dirname "$dsuite_real")")
    if command -v git >/dev/null 2>&1 && git -C "$dsuite_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      actual_commit=$(git -C "$dsuite_repo" rev-parse HEAD 2>/dev/null || true)
      if [[ "$actual_commit" == "$EXPECTED_DSUITE_COMMIT" || "$actual_commit" == "$EXPECTED_DSUITE_COMMIT"* ]]; then
        printf "[OK]   %-20s %s\n" "Dsuite target commit" "$actual_commit"
      else
        printf "[WARN] %-20s expected %s; found %s\n" "Dsuite target commit" "$EXPECTED_DSUITE_COMMIT" "${actual_commit:-UNKNOWN}" >&2
      fi
    else
      printf "[WARN] %-20s commit could not be detected from %s\n" "Dsuite target commit" "$dsuite_path" >&2
    fi
  fi
fi

echo
if [[ "$fail" -ne 0 ]]; then
  if [[ "$mode" == "tests" ]]; then
    echo "Local test prerequisites are incomplete. Bash >=4 is required; see INSTALL.md."
  else
    echo "One or more required runtime executables are missing or too old. See INSTALL.md."
  fi
  exit 1
fi

if [[ "$mode" == "tests" ]]; then
  echo "D-BPP local test prerequisites are available."
else
  echo "D-BPP core runtime dependencies are available."
fi

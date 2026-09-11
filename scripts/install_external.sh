#!/usr/bin/env bash
set -euo pipefail

PINNED_BPP_VERSION="4.8.7"
PINNED_DSUITE_COMMIT="a547f99599d763c1760548191ea3f62cc58e8ac3"
DSUITE_REPO="https://github.com/millanek/Dsuite.git"
BPP_API_URL="https://api.github.com/repos/bpp/bpp/releases/latest"
BPP_REPO_BASE="https://github.com/bpp/bpp/releases/download"
BUILD_JOBS="${DBPP_BUILD_JOBS:-2}"
NETWORK_RETRIES="${DBPP_NETWORK_RETRIES:-5}"
NETWORK_RETRY_DELAY="${DBPP_NETWORK_RETRY_DELAY:-5}"

BPP_VERSION_OVERRIDE="${BPP_VERSION-}"
DSUITE_COMMIT_OVERRIDE="${DSUITE_COMMIT-}"

# D-BPP v1.2 release candidates before this fix exported DSUITE_COMMIT from
# activate.d.  Treat that legacy value as installer metadata, not as a user
# override, so a normal rerun (including --latest) remains deterministic.
if [[ -n "$DSUITE_COMMIT_OVERRIDE"       && -n "${DBPP_EXPECTED_DSUITE_COMMIT:-}"       && "$DSUITE_COMMIT_OVERRIDE" == "$DBPP_EXPECTED_DSUITE_COMMIT" ]]; then
  DSUITE_COMMIT_OVERRIDE=""
fi
LATEST=false

usage() {
  cat <<'USAGE'
Usage: bash scripts/install_external.sh [--latest]

Default behavior installs the external dependency versions pinned and tested
for D-BPP Workflow v1.2:
  BPP 4.8.7
  Dsuite commit a547f99599d763c1760548191ea3f62cc58e8ac3

Optional modes:
  BPP_VERSION=<version> bash scripts/install_external.sh
      Install a specific BPP release while keeping the release-pinned Dsuite.

  DSUITE_COMMIT=<commit> bash scripts/install_external.sh
      Install a specific Dsuite Git commit while keeping the release-pinned BPP.

  BPP_VERSION=<version> DSUITE_COMMIT=<commit> bash scripts/install_external.sh
      Install explicitly selected versions of both external dependencies.

  bash scripts/install_external.sh --latest
      Query GitHub at install time and install the latest BPP release plus the
      current Dsuite default-branch HEAD. This mode is intended for compatibility
      testing, not exact reproduction of the D-BPP Workflow v1.2 environment.

Environment:
  DBPP_BUILD_JOBS=<N>       Number of parallel jobs used to compile Dsuite (default: 2).
  DBPP_NETWORK_RETRIES=<N>  Network attempts for BPP download and Dsuite Git operations (default: 5).
  DBPP_NETWORK_RETRY_DELAY=<seconds>  Delay between network attempts (default: 5).
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' was not found. Recreate the dbpp environment from environment.yml."
}

validate_retry_settings() {
  [[ "$NETWORK_RETRIES" =~ ^[1-9][0-9]*$ ]] || fail "DBPP_NETWORK_RETRIES must be a positive integer."
  [[ "$NETWORK_RETRY_DELAY" =~ ^[0-9]+$ ]] || fail "DBPP_NETWORK_RETRY_DELAY must be a non-negative integer."
}

retry_git_ls_remote() {
  local attempt output
  for ((attempt=1; attempt<=NETWORK_RETRIES; attempt++)); do
    if output=$(git ls-remote "$DSUITE_REPO" HEAD 2>/dev/null); then
      printf '%s\n' "$output"
      return 0
    fi
    if (( attempt < NETWORK_RETRIES )); then
      echo "WARNING: Dsuite remote query failed (attempt ${attempt}/${NETWORK_RETRIES}); retrying in ${NETWORK_RETRY_DELAY}s..." >&2
      sleep "$NETWORK_RETRY_DELAY"
    fi
  done
  return 1
}

clone_dsuite_with_retry() {
  local destination="$1"
  local attempt
  for ((attempt=1; attempt<=NETWORK_RETRIES; attempt++)); do
    rm -rf "$destination"
    echo "Dsuite clone attempt ${attempt}/${NETWORK_RETRIES}..."
    if git clone "$DSUITE_REPO" "$destination"; then
      return 0
    fi
    if (( attempt < NETWORK_RETRIES )); then
      echo "WARNING: Dsuite clone failed; retrying in ${NETWORK_RETRY_DELAY}s..." >&2
      sleep "$NETWORK_RETRY_DELAY"
    fi
  done
  return 1
}

fetch_dsuite_with_retry() {
  local destination="$1"
  local attempt
  for ((attempt=1; attempt<=NETWORK_RETRIES; attempt++)); do
    if git -C "$destination" fetch --all --tags --prune; then
      return 0
    fi
    if (( attempt < NETWORK_RETRIES )); then
      echo "WARNING: Dsuite fetch failed (attempt ${attempt}/${NETWORK_RETRIES}); retrying in ${NETWORK_RETRY_DELAY}s..." >&2
      sleep "$NETWORK_RETRY_DELAY"
    fi
  done
  return 1
}

download_bpp_with_retry() {
  local url="$1"
  local output="$2"
  local part="${output}.part"
  local attempt
  rm -f "$part"
  for ((attempt=1; attempt<=NETWORK_RETRIES; attempt++)); do
    echo "BPP download attempt ${attempt}/${NETWORK_RETRIES}..."
    rm -f "$part"
    if wget --timeout=30 --tries=1 --retry-connrefused -O "$part" "$url"; then
      if tar -tzf "$part" >/dev/null 2>&1; then
        mv -f "$part" "$output"
        return 0
      fi
      echo "WARNING: downloaded BPP archive failed integrity check." >&2
    fi
    if (( attempt < NETWORK_RETRIES )); then
      echo "WARNING: BPP download failed (attempt ${attempt}/${NETWORK_RETRIES}); retrying in ${NETWORK_RETRY_DELAY}s..." >&2
      sleep "$NETWORK_RETRY_DELAY"
    fi
  done
  rm -f "$part"
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest)
      LATEST=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$LATEST" == true && ( -n "$BPP_VERSION_OVERRIDE" || -n "$DSUITE_COMMIT_OVERRIDE" ) ]]; then
  fail "--latest cannot be combined with BPP_VERSION or DSUITE_COMMIT overrides."
fi

validate_retry_settings

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  fail "No active Conda environment detected. Run 'conda activate dbpp' first."
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "Automatic BPP/Dsuite installation is currently supported on Linux only. Install the external programs manually on this platform and then run scripts/check_dependencies.sh."
fi

for cmd in git make g++ wget tar ln readlink python awk; do
  require_cmd "$cmd"
done

latest_bpp_version() {
  local version
  version=$(wget -qO- "$BPP_API_URL" | python -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as exc:
    raise SystemExit(f"Could not parse GitHub release metadata: {exc}")
tag = str(data.get("tag_name", "")).strip()
if not tag:
    raise SystemExit("GitHub release metadata did not contain tag_name")
print(tag[1:] if tag.startswith("v") else tag)
') || fail "Could not determine the latest BPP release from GitHub. Use BPP_VERSION=<version> instead."
  [[ -n "$version" ]] || fail "Latest BPP release query returned an empty version."
  printf '%s\n' "$version"
}

latest_dsuite_commit() {
  local commit
  commit=$(retry_git_ls_remote | awk 'NR==1 {print $1}') || fail "Could not query the current Dsuite HEAD after ${NETWORK_RETRIES} attempts."
  [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]] || fail "Could not determine a valid Dsuite HEAD commit."
  printf '%s\n' "$commit"
}

INSTALL_MODE="release-pinned"
if [[ "$LATEST" == true ]]; then
  INSTALL_MODE="latest"
  echo "WARNING: --latest installs unpinned external dependencies." >&2
  echo "         Use this mode for compatibility testing, not exact v1.2 reproduction." >&2
  BPP_VERSION=$(latest_bpp_version)
  DSUITE_COMMIT=$(latest_dsuite_commit)
else
  BPP_VERSION="${BPP_VERSION_OVERRIDE:-$PINNED_BPP_VERSION}"
  DSUITE_COMMIT="${DSUITE_COMMIT_OVERRIDE:-$PINNED_DSUITE_COMMIT}"
  if [[ -n "$BPP_VERSION_OVERRIDE" || -n "$DSUITE_COMMIT_OVERRIDE" ]]; then
    INSTALL_MODE="custom"
    echo "WARNING: installing user-selected external dependency versions." >&2
    echo "         Run the bundled tests before production analyses." >&2
  fi
fi

BPP_VERSION="${BPP_VERSION#v}"
[[ "$BPP_VERSION" =~ ^[0-9]+([.][0-9]+){1,3}([._+-][A-Za-z0-9.-]+)?$ ]] || \
  fail "Invalid BPP_VERSION '$BPP_VERSION'. Expected a release version such as 4.8.7."
[[ "$DSUITE_COMMIT" =~ ^[0-9a-fA-F]{7,40}$ ]] || \
  fail "Invalid DSUITE_COMMIT '$DSUITE_COMMIT'. Expected a Git commit hash."

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    BPP_ARCH="linux-x86_64"
    ;;
  aarch64|arm64)
    BPP_ARCH="linux-aarch64"
    ;;
  *)
    fail "Automatic BPP installation for architecture '$ARCH' is not configured. Install BPP ${BPP_VERSION} manually, then install Dsuite at commit ${DSUITE_COMMIT}."
    ;;
esac

INSTALL_ROOT="$CONDA_PREFIX/opt/dbpp-external"
mkdir -p "$INSTALL_ROOT"
METADATA_FILE="$INSTALL_ROOT/install_metadata.tsv"

printf '%s\n' "================================================="
printf 'External dependency mode: %s\n' "$INSTALL_MODE"
printf 'BPP target:              %s\n' "$BPP_VERSION"
printf 'Dsuite target commit:    %s\n' "$DSUITE_COMMIT"
printf '%s\n' "================================================="

printf '\n%s\n' "================================================="
printf '%s\n' "Installing BPP ${BPP_VERSION}"
printf '%s\n' "================================================="

BPP_DIR="$INSTALL_ROOT/bpp-${BPP_VERSION}-${BPP_ARCH}"
BPP_TARBALL="$INSTALL_ROOT/bpp-${BPP_VERSION}-${BPP_ARCH}.tar.gz"
BPP_URL="${BPP_REPO_BASE}/v${BPP_VERSION}/bpp-${BPP_VERSION}-${BPP_ARCH}.tar.gz"

if [[ ! -x "$BPP_DIR/bin/bpp" ]]; then
  rm -rf "$BPP_DIR"
  if ! download_bpp_with_retry "$BPP_URL" "$BPP_TARBALL"; then
    fail "BPP ${BPP_VERSION} could not be downloaded for ${BPP_ARCH} after ${NETWORK_RETRIES} attempts. Check network access and that this release provides the expected binary asset, or install BPP manually."
  fi
  tar -xzf "$BPP_TARBALL" -C "$INSTALL_ROOT"
fi

[[ -x "$BPP_DIR/bin/bpp" ]] || fail "BPP executable was not found at '$BPP_DIR/bin/bpp' after extraction."
ln -sfn "$BPP_DIR/bin/bpp" "$CONDA_PREFIX/bin/bpp"

printf '\n%s\n' "================================================="
printf '%s\n' "Installing Dsuite"
printf '%s\n' "Target commit: ${DSUITE_COMMIT}"
printf '%s\n' "================================================="

DSUITE_DIR="$INSTALL_ROOT/Dsuite"
if [[ ! -d "$DSUITE_DIR/.git" ]]; then
  if ! clone_dsuite_with_retry "$DSUITE_DIR"; then
    fail "Dsuite could not be cloned after ${NETWORK_RETRIES} attempts. Check network access to GitHub and rerun the installer."
  fi
fi

if ! fetch_dsuite_with_retry "$DSUITE_DIR"; then
  fail "Dsuite repository could not be updated after ${NETWORK_RETRIES} attempts. Check network access to GitHub and rerun the installer."
fi
if ! git -C "$DSUITE_DIR" checkout --detach "$DSUITE_COMMIT"; then
  fail "Dsuite commit '$DSUITE_COMMIT' could not be checked out."
fi

make -C "$DSUITE_DIR" clean >/dev/null 2>&1 || true
make -C "$DSUITE_DIR" -j "$BUILD_JOBS"

[[ -x "$DSUITE_DIR/Build/Dsuite" ]] || fail "Dsuite compilation did not produce '$DSUITE_DIR/Build/Dsuite'."
ln -sfn "$DSUITE_DIR/Build/Dsuite" "$CONDA_PREFIX/bin/Dsuite"

ACTUAL_DSUITE_COMMIT=$(git -C "$DSUITE_DIR" rev-parse HEAD)
[[ "$ACTUAL_DSUITE_COMMIT" == "$DSUITE_COMMIT" || "$ACTUAL_DSUITE_COMMIT" == "$DSUITE_COMMIT"* ]] || \
  fail "Installed Dsuite commit '$ACTUAL_DSUITE_COMMIT' does not match requested commit '$DSUITE_COMMIT'."

BPP_VERSION_OUTPUT=$(bpp --version 2>&1 || true)
ACTUAL_BPP_VERSION=$(printf '%s\n' "$BPP_VERSION_OUTPUT" | sed -n 's/^bpp v\([^_ ,]*\).*/\1/p' | head -n1)
[[ -n "$ACTUAL_BPP_VERSION" ]] || ACTUAL_BPP_VERSION="$BPP_VERSION"

{
  printf "key\tvalue\n"
  printf "install_mode\t%s\n" "$INSTALL_MODE"
  printf "bpp_version\t%s\n" "$ACTUAL_BPP_VERSION"
  printf "bpp_requested\t%s\n" "$BPP_VERSION"
  printf "dsuite_commit\t%s\n" "$ACTUAL_DSUITE_COMMIT"
  printf "dsuite_requested\t%s\n" "$DSUITE_COMMIT"
} > "$METADATA_FILE"

ACTIVATE_DIR="$CONDA_PREFIX/etc/conda/activate.d"
mkdir -p "$ACTIVATE_DIR"
cat > "$ACTIVATE_DIR/dbpp_external.sh" <<ACTIVATE_EOF
# Generated by D-BPP Workflow v1.2 scripts/install_external.sh
export DBPP_EXPECTED_BPP_VERSION="${ACTUAL_BPP_VERSION}"
export DBPP_EXPECTED_DSUITE_COMMIT="${ACTUAL_DSUITE_COMMIT}"
export DBPP_EXTERNAL_INSTALL_MODE="${INSTALL_MODE}"
ACTIVATE_EOF

printf '\n%s\n' "================================================="
printf '%s\n' "External installation complete"
printf '%s\n' "================================================="
printf 'Installation mode:   %s\n' "$INSTALL_MODE"
printf 'BPP executable:      %s\n' "$(command -v bpp)"
printf 'Dsuite executable:   %s\n' "$(command -v Dsuite)"
printf 'Dsuite commit:       %s\n' "$ACTUAL_DSUITE_COMMIT"
printf 'Installation record: %s\n' "$METADATA_FILE"
printf '\n'
bpp --version 2>&1 | head -n 3 || true
printf '\n'
Dsuite 2>&1 | head -n 4 || true
printf '\nRun: bash scripts/check_dependencies.sh\n'

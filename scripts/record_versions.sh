#!/usr/bin/env bash
set -euo pipefail

out="${1:-software_versions.tsv}"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

resolve_cmd() {
  command -v "$1" 2>/dev/null || true
}

real_path() {
  local p="$1"
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

conda_pkg_version() {
  local pkg="$1"
  if [[ -n "${CONDA_PREFIX:-}" && -d "$CONDA_PREFIX/conda-meta" ]] && command -v python >/dev/null 2>&1; then
    python - "$CONDA_PREFIX" "$pkg" <<'PY'
import glob, json, os, sys
prefix, pkg = sys.argv[1:]
for path in glob.glob(os.path.join(prefix, "conda-meta", f"{pkg}-*.json")):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if data.get("name") == pkg:
            print(data.get("version", "UNKNOWN"))
            raise SystemExit
    except (OSError, json.JSONDecodeError):
        pass
print("UNKNOWN")
PY
  else
    printf 'UNKNOWN\n'
  fi
}

metadata_value() {
  local file="$1"
  local key="$2"
  awk -F '\t' -v key="$key" '$1 == key {print $2; exit}' "$file" 2>/dev/null || true
}

external_mode="NOT_RECORDED"
metadata_file=""
if [[ -n "${CONDA_PREFIX:-}" ]]; then
  candidate="$CONDA_PREFIX/opt/dbpp-external/install_metadata.tsv"
  if [[ -f "$candidate" ]]; then
    metadata_file="$candidate"
    external_mode=$(metadata_value "$candidate" install_mode)
    [[ -n "$external_mode" ]] || external_mode="UNKNOWN"
  fi
fi

bash_version="NOT_FOUND"
command -v bash >/dev/null 2>&1 && bash_version=$(bash --version 2>/dev/null | head -n1 || true)
python_version="NOT_FOUND"
command -v python >/dev/null 2>&1 && python_version=$(python --version 2>&1 | awk '{print $2}' || true)
perl_version="NOT_FOUND"
command -v perl >/dev/null 2>&1 && perl_version=$(perl -e 'printf "%vd", $^V' 2>/dev/null || true)
snp_sites_version="NOT_FOUND"
command -v snp-sites >/dev/null 2>&1 && snp_sites_version=$(snp-sites -V 2>&1 | head -n1 | tr '\t' ' ' || true)
newick_version=$(conda_pkg_version newick_utils)

dsuite_version="NOT_FOUND"
dsuite_commit=""
dsuite_path=$(resolve_cmd Dsuite)
if [[ -n "$dsuite_path" ]]; then
  dsuite_output=$(Dsuite 2>&1 || true)
  dsuite_version=$(printf '%s\n' "$dsuite_output" | awk -F':[[:space:]]*' '/^Version:/ {print $2; exit}')
  [[ -n "$dsuite_version" ]] || dsuite_version=$(printf '%s\n' "$dsuite_output" | awk 'NF {print; exit}' | tr '\t' ' ' || true)

  # Prefer the commit of the executable that is actually on PATH.
  dsuite_real=$(real_path "$dsuite_path")
  dsuite_repo=$(dirname "$(dirname "$dsuite_real")")
  if command -v git >/dev/null 2>&1 && git -C "$dsuite_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dsuite_commit=$(git -C "$dsuite_repo" rev-parse HEAD 2>/dev/null || true)
  fi
fi
if [[ -z "$dsuite_commit" && -n "$metadata_file" ]]; then
  dsuite_commit=$(metadata_value "$metadata_file" dsuite_commit)
fi
if [[ -z "$dsuite_commit" && -n "${DSUITE_COMMIT:-}" ]]; then
  dsuite_commit="$DSUITE_COMMIT"
fi
[[ -n "$dsuite_commit" ]] || dsuite_commit="NOT_RECORDED"

bpp_version="NOT_FOUND"
bpp_path=$(resolve_cmd bpp)
if [[ -n "$bpp_path" ]]; then
  bpp_output=$(bpp --version 2>&1 || true)
  bpp_version=$(printf '%s\n' "$bpp_output" | awk '/^bpp v/ {print; exit}')
  [[ -n "$bpp_version" ]] || bpp_version=$(printf '%s\n' "$bpp_output" | awk 'NF {print; exit}' | tr '\t' ' ' || true)
fi

{
  printf "component\tversion_or_revision\texecutable_or_location\n"
  printf "D-BPP_Workflow\t%s\t%s\n" "${DBPP_VERSION:-v1.2}" "$repo_root"
  printf "External_dependency_mode\t%s\t%s\n" "$external_mode" "${metadata_file:-NOT_RECORDED}"
  printf "Bash\t%s\t%s\n" "$bash_version" "$(resolve_cmd bash)"
  printf "Python\t%s\t%s\n" "$python_version" "$(resolve_cmd python)"
  printf "Perl\t%s\t%s\n" "$perl_version" "$(resolve_cmd perl)"
  printf "SNP-sites\t%s\t%s\n" "$snp_sites_version" "$(resolve_cmd snp-sites)"
  printf "Newick_Utilities\t%s\t%s\n" "$newick_version" "$(resolve_cmd nw_prune)"
  printf "Dsuite\t%s; commit=%s\t%s\n" "$dsuite_version" "$dsuite_commit" "$dsuite_path"
  printf "BPP\t%s\t%s\n" "$bpp_version" "$bpp_path"
} > "$out"

echo "Wrote $out"
if [[ "$dsuite_commit" == "NOT_RECORDED" ]]; then
  echo "WARNING: Dsuite Git commit could not be detected. Set DSUITE_COMMIT=<commit> and rerun before archiving a release reproducibility record." >&2
fi
if [[ "$external_mode" != "release-pinned" && "$external_mode" != "NOT_RECORDED" ]]; then
  echo "WARNING: external dependency mode is '$external_mode', not the exact v1.2 release-pinned environment." >&2
fi

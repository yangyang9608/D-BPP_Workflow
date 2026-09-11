#!/usr/bin/env python3
"""Utilities for BPP marginal-likelihood calculations by thermodynamic integration.

The v1.2 interface separates execution records from numerical results:

1. ``prepare`` runs ``bpp --bfdriver`` and records the generated quadrature setup.
2. ``run`` executes the generated power-posterior control files and stores logs/manifest.
3. ``summarize`` reads the recorded BPP screen logs, validates integration-point completeness, and calculates log marginal likelihood.
4. ``compare`` ranks final-network models from one or more summary tables.

A backward-compatible legacy invocation is also supported:

    cal_marginal_likelihoods.py betaweights.csv "model-*.out" report.txt
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
from dataclasses import dataclass
from datetime import datetime, timezone
import glob
import math
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
from typing import Iterable, Sequence


FLOAT_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
BFBETA_RE = re.compile(
    rf"BFbeta\s*=\s*({FLOAT_RE}).*?E_b\(lnf\(X\)\)\s*=\s*({FLOAT_RE})",
    re.DOTALL,
)
BETA_RE = re.compile(
    rf"\bbeta\s*=\s*({FLOAT_RE}).*?E_b\(lnf\(X\)\)\s*=\s*({FLOAT_RE})",
    re.DOTALL | re.IGNORECASE,
)


@dataclass(frozen=True)
class BetaWeight:
    beta: float
    weight: float


@dataclass(frozen=True)
class PowerPosteriorResult:
    filename: Path
    beta: float
    expected_log_likelihood: float


@dataclass(frozen=True)
class Contribution:
    filename: Path
    beta: float
    weight: float
    expected_log_likelihood: float
    value: float


@dataclass(frozen=True)
class RunRecord:
    control_file: Path
    log_file: Path
    return_code: int
    elapsed_seconds: float
    started_utc: str
    finished_utc: str


@dataclass(frozen=True)
class ModelSummary:
    model: str
    log_marginal_likelihood: float
    n_points: int
    source: Path


def _nonempty_noncomment_lines(path: Path) -> list[str]:
    lines: list[str] = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            lines.append(stripped)
    return lines


def parse_betaweights_file(betaweights_file: Path) -> list[BetaWeight]:
    """Read beta/weight values produced by BPP's BFdriver.

    Both current comma-delimited files with named columns and older whitespace-delimited
    beta/weight files are accepted.
    """
    lines = _nonempty_noncomment_lines(betaweights_file)
    if not lines:
        raise ValueError("the beta-weights file is empty")

    points: list[BetaWeight] = []
    if "," in lines[0]:
        reader = csv.reader(lines)
        rows = list(reader)
        header = [field.strip().lower() for field in rows[0]]
        has_header = "beta" in header and "weight" in header
        if has_header:
            beta_index = header.index("beta")
            weight_index = header.index("weight")
            data_rows = rows[1:]
            start_line = 2
        else:
            beta_index, weight_index = 0, 1
            data_rows = rows
            start_line = 1

        for line_number, row in enumerate(data_rows, start=start_line):
            if max(beta_index, weight_index) >= len(row):
                raise ValueError(f"line {line_number} is missing beta or weight")
            points.append(_validate_beta_weight(row[beta_index], row[weight_index], line_number))
    else:
        first_fields = lines[0].split()
        has_header = any(re.search(r"[A-Za-z]", field) for field in first_fields)
        data_lines = lines[1:] if has_header else lines
        for line_number, line in enumerate(data_lines, start=2 if has_header else 1):
            fields = line.split()
            if len(fields) < 2:
                raise ValueError(f"line {line_number} is missing beta or weight")
            points.append(_validate_beta_weight(fields[0], fields[1], line_number))

    if not points:
        raise ValueError("the beta-weights file contains no quadrature points")

    seen: list[float] = []
    for point in points:
        if any(math.isclose(point.beta, old, rel_tol=0, abs_tol=1e-12) for old in seen):
            raise ValueError(f"duplicate beta value in beta-weights file: {point.beta}")
        seen.append(point.beta)

    weight_sum = sum(point.weight for point in points)
    if not math.isclose(weight_sum, 2.0, rel_tol=1e-5, abs_tol=1e-5):
        raise ValueError(
            f"quadrature weights sum to {weight_sum:.10g}, but BPP Gauss-Legendre weights should sum to 2"
        )
    return sorted(points, key=lambda point: point.beta)


def _validate_beta_weight(beta_text: str, weight_text: str, line_number: int) -> BetaWeight:
    try:
        beta = float(beta_text)
        weight = float(weight_text)
    except ValueError as exc:
        raise ValueError(f"line {line_number} has a non-numeric beta or weight") from exc
    if not (math.isfinite(beta) and math.isfinite(weight)):
        raise ValueError(f"line {line_number} has a non-finite beta or weight")
    if not 0 <= beta <= 1:
        raise ValueError(f"line {line_number} has beta outside [0, 1]: {beta}")
    if weight <= 0:
        raise ValueError(f"line {line_number} has a non-positive weight: {weight}")
    return BetaWeight(beta, weight)


def parse_power_posterior_file(output_file: Path) -> PowerPosteriorResult:
    content = output_file.read_text(encoding="utf-8", errors="replace")
    matches = BFBETA_RE.findall(content)
    if not matches:
        matches = BETA_RE.findall(content)
    if not matches:
        raise ValueError(
            f"no 'BFbeta ... E_b(lnf(X))' record was found in '{output_file}'"
        )

    beta_text, expectation_text = matches[-1]
    beta = float(beta_text)
    expected_log_likelihood = float(expectation_text)
    if not (math.isfinite(beta) and math.isfinite(expected_log_likelihood)):
        raise ValueError(f"non-finite BFbeta result in '{output_file}'")
    return PowerPosteriorResult(output_file, beta, expected_log_likelihood)


def read_power_posterior_paths(paths: Sequence[Path]) -> list[PowerPosteriorResult]:
    filenames = sorted(Path(path).resolve() for path in paths)
    if not filenames:
        raise ValueError("no power-posterior files were provided")
    for filename in filenames:
        if not filename.is_file():
            raise ValueError(f"power-posterior file does not exist: {filename}")
    results = [parse_power_posterior_file(filename) for filename in filenames]

    seen: list[float] = []
    for result in results:
        if any(math.isclose(result.beta, old, rel_tol=0, abs_tol=1e-12) for old in seen):
            raise ValueError(
                f"duplicate power-posterior beta detected near {result.beta:g}; "
                "make the input set more specific"
            )
        seen.append(result.beta)
    return results


def read_power_posterior_files(pattern: str) -> list[PowerPosteriorResult]:
    filenames = sorted(Path(name) for name in glob.glob(pattern))
    if not filenames:
        raise ValueError(f"no files matched pattern: {pattern}")
    return read_power_posterior_paths(filenames)


def read_run_manifest_logs(run_dir: Path) -> tuple[list[PowerPosteriorResult], str]:
    manifest = run_dir / "run_manifest.tsv"
    if not manifest.is_file():
        raise ValueError(f"run manifest does not exist: {manifest}")

    log_files: list[Path] = []
    with manifest.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"log_file", "return_code", "status"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError(f"run manifest has an unexpected header: {manifest}")
        for row_number, row in enumerate(reader, start=2):
            if row["return_code"] != "0" or row["status"] != "OK":
                raise ValueError(
                    f"run manifest contains a failed power-posterior run on line {row_number}; "
                    "resolve failed runs before summarizing"
                )
            log_files.append(Path(row["log_file"]))

    if not log_files:
        raise ValueError(f"run manifest contains no completed runs: {manifest}")
    return read_power_posterior_paths(log_files), f"run_manifest:{manifest.resolve()}"


def calculate_marginal_likelihood(
    points: Sequence[BetaWeight],
    results: Sequence[PowerPosteriorResult],
    beta_tolerance: float = 1e-6,
) -> tuple[float, list[Contribution]]:
    """Match power-posterior runs to quadrature points and integrate them."""
    if beta_tolerance <= 0:
        raise ValueError("beta tolerance must be greater than 0")

    unmatched = set(range(len(points)))
    contributions: list[Contribution] = []
    for result in results:
        candidates = sorted(unmatched, key=lambda index: abs(points[index].beta - result.beta))
        if not candidates:
            raise ValueError(
                f"more output files than quadrature points; duplicate beta near {result.beta}"
            )
        index = candidates[0]
        point = points[index]
        difference = abs(point.beta - result.beta)
        if difference > beta_tolerance:
            raise ValueError(
                f"beta {result.beta:.10g} from '{result.filename}' has no beta-weight match "
                f"within tolerance {beta_tolerance:g}"
            )
        unmatched.remove(index)
        value = point.weight * result.expected_log_likelihood / 2.0
        contributions.append(
            Contribution(
                filename=result.filename,
                beta=point.beta,
                weight=point.weight,
                expected_log_likelihood=result.expected_log_likelihood,
                value=value,
            )
        )

    if unmatched:
        missing = ", ".join(f"{points[index].beta:.10g}" for index in sorted(unmatched))
        raise ValueError(f"missing BPP output for beta value(s): {missing}")

    contributions.sort(key=lambda item: item.beta)
    return sum(item.value for item in contributions), contributions


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def resolve_executable(name_or_path: str) -> str:
    if "/" in name_or_path or name_or_path.startswith("."):
        path = Path(name_or_path).expanduser().resolve()
        if not path.is_file():
            raise ValueError(f"BPP executable does not exist: {path}")
        return str(path)
    found = shutil.which(name_or_path)
    if not found:
        raise ValueError(f"BPP executable was not found in PATH: {name_or_path}")
    return found


def prepare_bfdriver(
    control_file: Path,
    points: int,
    bpp_executable: str,
    run_dir: Path,
) -> list[Path]:
    if points <= 0:
        raise ValueError("--points must be greater than 0")
    if not control_file.is_file():
        raise ValueError(f"control file does not exist: {control_file}")

    bpp = resolve_executable(bpp_executable)
    run_dir.mkdir(parents=True, exist_ok=True)
    log_file = run_dir / "bfdriver.log"
    manifest = run_dir / "bfdriver_manifest.tsv"

    parent = control_file.resolve().parent
    stem = control_file.stem
    before_controls = {path.resolve() for path in parent.glob("*.ctl")}
    before_betaweights = {path.resolve() for path in parent.glob("*betaweight*")}
    command = [bpp, "--bfdriver", control_file.name, "--points", str(points)]
    started = utc_now()
    t0 = time.perf_counter()
    with log_file.open("w", encoding="utf-8") as log:
        log.write("Command: " + shlex.join(command) + "\n\n")
        log.flush()
        completed = subprocess.run(
            command,
            cwd=parent,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    elapsed = time.perf_counter() - t0
    finished = utc_now()
    if completed.returncode != 0:
        raise ValueError(
            f"BPP BFdriver failed with exit code {completed.returncode}; see {log_file}"
        )

    after_controls = {path.resolve() for path in parent.glob("*.ctl")}
    generated = sorted(after_controls - before_controls)
    # If files already existed and were overwritten, fall back to common BFdriver names.
    if not generated:
        generated = sorted(path.resolve() for path in parent.glob(f"{stem}.b*.ctl"))
    if not generated:
        raise ValueError(
            f"BFdriver completed but no generated power-posterior control files were detected in {parent}"
        )

    after_betaweights = {path.resolve() for path in parent.glob("*betaweight*")}
    betaweight_candidates = sorted(after_betaweights - before_betaweights)
    if not betaweight_candidates:
        betaweight_candidates = sorted(
            {path.resolve() for path in parent.glob("*betaweight*")}
            | {path.resolve() for path in parent.glob("betaweights.txt")}
        )

    with manifest.open("w", encoding="utf-8") as handle:
        handle.write("item\tvalue\n")
        handle.write(f"control_file\t{control_file.resolve()}\n")
        handle.write(f"points\t{points}\n")
        handle.write(f"bpp\t{bpp}\n")
        handle.write(f"started_utc\t{started}\n")
        handle.write(f"finished_utc\t{finished}\n")
        handle.write(f"elapsed_seconds\t{elapsed:.6f}\n")
        for path in generated:
            handle.write(f"generated_control\t{path}\n")
        for path in betaweight_candidates:
            handle.write(f"betaweights_candidate\t{path.resolve()}\n")

    return generated


def _run_one_control(control_file: Path, bpp: str, log_file: Path) -> RunRecord:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    command = [bpp, "--cfile", control_file.name]
    started = utc_now()
    t0 = time.perf_counter()
    with log_file.open("w", encoding="utf-8") as log:
        log.write("Command: " + shlex.join(command) + "\n\n")
        log.flush()
        completed = subprocess.run(
            command,
            cwd=control_file.resolve().parent,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    elapsed = time.perf_counter() - t0
    finished = utc_now()
    return RunRecord(
        control_file=control_file.resolve(),
        log_file=log_file.resolve(),
        return_code=completed.returncode,
        elapsed_seconds=elapsed,
        started_utc=started,
        finished_utc=finished,
    )


def run_power_posteriors(
    control_pattern: str,
    bpp_executable: str,
    jobs: int,
    run_dir: Path,
) -> list[RunRecord]:
    if jobs <= 0:
        raise ValueError("--jobs must be greater than 0")
    controls = sorted(Path(name).resolve() for name in glob.glob(control_pattern))
    if not controls:
        raise ValueError(f"no control files matched pattern: {control_pattern}")
    for control in controls:
        if not control.is_file():
            raise ValueError(f"control file does not exist: {control}")

    bpp = resolve_executable(bpp_executable)
    logs_dir = run_dir / "logs"
    run_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    def task(index_control: tuple[int, Path]) -> RunRecord:
        index, control = index_control
        log_file = logs_dir / f"{index:03d}_{control.stem}.log"
        return _run_one_control(control, bpp, log_file)

    indexed = list(enumerate(controls, start=1))
    if jobs == 1:
        records = [task(item) for item in indexed]
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
            records = list(executor.map(task, indexed))

    records.sort(key=lambda record: str(record.control_file))
    manifest = run_dir / "run_manifest.tsv"
    with manifest.open("w", encoding="utf-8") as handle:
        handle.write(
            "control_file\tlog_file\treturn_code\tstatus\telapsed_seconds\t"
            "started_utc\tfinished_utc\n"
        )
        for record in records:
            handle.write(
                f"{record.control_file}\t{record.log_file}\t{record.return_code}\t"
                f"{'OK' if record.return_code == 0 else 'FAILED'}\t"
                f"{record.elapsed_seconds:.6f}\t{record.started_utc}\t{record.finished_utc}\n"
            )
    return records


def write_summary_outputs(
    output_dir: Path,
    model_label: str,
    betaweights_file: Path,
    output_pattern: str,
    marginal_likelihood: float,
    contributions: Sequence[Contribution],
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    details = output_dir / "integration_points.tsv"
    with details.open("w", encoding="utf-8") as handle:
        handle.write("beta\tweight\tElnfX\tcontribution\toutput_file\n")
        for item in contributions:
            handle.write(
                f"{item.beta:.10g}\t{item.weight:.10g}\t"
                f"{item.expected_log_likelihood:.10g}\t{item.value:.10g}\t"
                f"{item.filename.resolve()}\n"
            )

    summary = output_dir / "marginal_likelihood.tsv"
    with summary.open("w", encoding="utf-8") as handle:
        handle.write(
            "model\tlog_marginal_likelihood\tn_points\tbetaweights_file\toutput_pattern\n"
        )
        handle.write(
            f"{model_label}\t{marginal_likelihood:.10f}\t{len(contributions)}\t"
            f"{betaweights_file.resolve()}\t{output_pattern}\n"
        )

    report = output_dir / "marginal_likelihood_report.txt"
    with report.open("w", encoding="utf-8") as handle:
        handle.write(f"Model: {model_label}\n")
        handle.write(f"Integration points: {len(contributions)}\n")
        handle.write(f"Beta-weights file: {betaweights_file.resolve()}\n")
        handle.write(f"Output pattern: {output_pattern}\n")
        handle.write(
            "Formula: log p(X|M) ~= 0.5 * sum_i w_i * E_beta_i[log p(X|theta)]\n"
        )
        handle.write(f"Log marginal likelihood: {marginal_likelihood:.10f}\n\n")
        handle.write("Integration-point contributions\n")
        handle.write("beta\tweight\tElnfX\tcontribution\toutput_file\n")
        for item in contributions:
            handle.write(
                f"{item.beta:.10g}\t{item.weight:.10g}\t"
                f"{item.expected_log_likelihood:.10g}\t{item.value:.10g}\t"
                f"{item.filename.resolve()}\n"
            )


def parse_model_summary(summary_file: Path) -> ModelSummary:
    with summary_file.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows = list(reader)
    if len(rows) != 1:
        raise ValueError(
            f"summary file must contain exactly one model row: {summary_file}"
        )
    row = rows[0]
    required = {"model", "log_marginal_likelihood", "n_points"}
    if not required.issubset(row):
        raise ValueError(f"summary file lacks required columns: {summary_file}")
    try:
        log_ml = float(row["log_marginal_likelihood"])
        n_points = int(row["n_points"])
    except ValueError as exc:
        raise ValueError(f"invalid numeric value in summary file: {summary_file}") from exc
    if not math.isfinite(log_ml) or n_points <= 0:
        raise ValueError(f"invalid marginal-likelihood summary: {summary_file}")
    return ModelSummary(row["model"], log_ml, n_points, summary_file.resolve())


def write_comparison(output_dir: Path, summaries: Sequence[ModelSummary]) -> None:
    if len(summaries) < 2:
        raise ValueError("model comparison requires at least two marginal-likelihood summaries")
    labels = [item.model for item in summaries]
    if len(labels) != len(set(labels)):
        raise ValueError("model labels must be unique for comparison")

    ranked = sorted(summaries, key=lambda item: item.log_marginal_likelihood, reverse=True)
    best = ranked[0].log_marginal_likelihood
    output_dir.mkdir(parents=True, exist_ok=True)

    table = output_dir / "model_comparison.tsv"
    with table.open("w", encoding="utf-8") as handle:
        handle.write(
            "rank\tmodel\tlog_marginal_likelihood\tdelta_logML_from_best\t"
            "log_BF_best_vs_model\tn_points\tsource_summary\n"
        )
        for rank, item in enumerate(ranked, start=1):
            delta = best - item.log_marginal_likelihood
            handle.write(
                f"{rank}\t{item.model}\t{item.log_marginal_likelihood:.10f}\t"
                f"{delta:.10f}\t{delta:.10f}\t{item.n_points}\t{item.source}\n"
            )

    report = output_dir / "model_comparison_report.txt"
    with report.open("w", encoding="utf-8") as handle:
        handle.write("Marginal-likelihood comparison of final network models\n")
        handle.write(f"Best model: {ranked[0].model}\n")
        handle.write(
            f"Best log marginal likelihood: {ranked[0].log_marginal_likelihood:.10f}\n\n"
        )
        handle.write("rank\tmodel\tlogML\tdelta_from_best\n")
        for rank, item in enumerate(ranked, start=1):
            delta = best - item.log_marginal_likelihood
            handle.write(
                f"{rank}\t{item.model}\t{item.log_marginal_likelihood:.10f}\t{delta:.10f}\n"
            )


def add_common_bpp_option(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--bpp",
        default="bpp",
        help="BPP executable name or path (default: bpp from PATH)",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare, run, summarize and compare BPP thermodynamic-integration "
            "marginal-likelihood analyses."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare = subparsers.add_parser(
        "prepare", help="run BPP BFdriver and record generated quadrature control files"
    )
    prepare.add_argument("control_file", type=Path, help="validated BPP control file")
    prepare.add_argument(
        "--points", type=int, default=16, help="Gauss-Legendre points (default: 16)"
    )
    prepare.add_argument(
        "--run-dir",
        type=Path,
        default=Path("marginal_likelihood_run"),
        help="directory for BFdriver logs/manifest (default: marginal_likelihood_run)",
    )
    add_common_bpp_option(prepare)

    run = subparsers.add_parser(
        "run", help="run generated power-posterior control files and record logs"
    )
    run.add_argument(
        "control_pattern",
        help="quoted glob matching generated control files, e.g. 'model.b*.ctl'",
    )
    run.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="number of BPP processes to run concurrently (default: 1)",
    )
    run.add_argument(
        "--run-dir",
        type=Path,
        default=Path("marginal_likelihood_run"),
        help="directory for execution logs/manifest (default: marginal_likelihood_run)",
    )
    add_common_bpp_option(run)

    summarize = subparsers.add_parser(
        "summarize", help="validate all integration points and calculate log marginal likelihood"
    )
    summarize.add_argument("betaweights_file", type=Path, help="BFdriver beta/weight file")
    summarize.add_argument(
        "output_pattern",
        nargs="?",
        help=(
            "optional quoted glob matching files containing BFbeta/E_b(lnf(X)) records; "
            "if omitted, screen logs are read from --run-dir/run_manifest.tsv"
        ),
    )
    summarize.add_argument(
        "--run-dir",
        type=Path,
        default=Path("marginal_likelihood_run"),
        help=(
            "execution-record directory containing run_manifest.tsv when output_pattern is omitted "
            "(default: marginal_likelihood_run)"
        ),
    )
    summarize.add_argument(
        "--label",
        default="model",
        help="model label written to the summary table (default: model)",
    )
    summarize.add_argument(
        "--output-dir",
        type=Path,
        default=Path("marginal_likelihood_results"),
        help="result directory (default: marginal_likelihood_results)",
    )
    summarize.add_argument(
        "--beta-tolerance",
        type=float,
        default=1e-6,
        help="absolute tolerance when matching printed beta values (default: 1e-6)",
    )

    compare = subparsers.add_parser(
        "compare", help="rank two or more final-network models by log marginal likelihood"
    )
    compare.add_argument(
        "summary_files",
        nargs="+",
        type=Path,
        help="marginal_likelihood.tsv files produced by the summarize command",
    )
    compare.add_argument(
        "--output-dir",
        type=Path,
        default=Path("marginal_likelihood_comparison"),
        help="comparison output directory (default: marginal_likelihood_comparison)",
    )
    return parser


def legacy_main(argv: Sequence[str]) -> int:
    legacy = argparse.ArgumentParser(
        description="Legacy D-BPP marginal-likelihood calculator"
    )
    legacy.add_argument("betaweights_file", type=Path)
    legacy.add_argument("output_pattern")
    legacy.add_argument("output_file", type=Path)
    legacy.add_argument("--beta-tolerance", type=float, default=1e-6)
    args = legacy.parse_args(argv)

    if not args.betaweights_file.is_file():
        print(
            f"ERROR: beta-weights file does not exist: {args.betaweights_file}",
            file=sys.stderr,
        )
        return 1
    try:
        points = parse_betaweights_file(args.betaweights_file)
        results = read_power_posterior_files(args.output_pattern)
        marginal_likelihood, contributions = calculate_marginal_likelihood(
            points, results, args.beta_tolerance
        )
        args.output_file.parent.mkdir(parents=True, exist_ok=True)
        with args.output_file.open("w", encoding="utf-8") as handle:
            handle.write(f"Log marginal likelihood: {marginal_likelihood:.10f}\n\n")
            handle.write("Filename\tbeta\tweight\tElnfX\tcontribution\n")
            for item in contributions:
                handle.write(
                    f"{item.filename.name}\t{item.beta:.10g}\t{item.weight:.10g}\t"
                    f"{item.expected_log_likelihood:.10g}\t{item.value:.10g}\n"
                )
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Parsed {len(contributions)} power-posterior runs")
    print(f"Log marginal likelihood: {marginal_likelihood:.10f}")
    print(f"Report written to: {args.output_file}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    commands = {"prepare", "run", "summarize", "compare"}
    # Keep v1.0/v1.1 positional syntax working for existing users.
    if argv and argv[0] not in commands and argv[0] not in {"-h", "--help"}:
        return legacy_main(argv)

    args = build_parser().parse_args(argv)
    try:
        if args.command == "prepare":
            generated = prepare_bfdriver(
                args.control_file, args.points, args.bpp, args.run_dir
            )
            print(f"BFdriver generated/found {len(generated)} power-posterior control files")
            for path in generated:
                print(path)
            print(f"Preparation records: {args.run_dir}")
            return 0

        if args.command == "run":
            records = run_power_posteriors(
                args.control_pattern, args.bpp, args.jobs, args.run_dir
            )
            failed = [record for record in records if record.return_code != 0]
            print(f"Completed {len(records)} power-posterior run(s)")
            print(f"Execution records: {args.run_dir}")
            if failed:
                print(
                    f"ERROR: {len(failed)} run(s) failed; see {args.run_dir / 'run_manifest.tsv'}",
                    file=sys.stderr,
                )
                return 1
            return 0

        if args.command == "summarize":
            if not args.betaweights_file.is_file():
                raise ValueError(
                    f"beta-weights file does not exist: {args.betaweights_file}"
                )
            points = parse_betaweights_file(args.betaweights_file)
            if args.output_pattern:
                results = read_power_posterior_files(args.output_pattern)
                output_source = args.output_pattern
            else:
                results, output_source = read_run_manifest_logs(args.run_dir)
            marginal_likelihood, contributions = calculate_marginal_likelihood(
                points, results, args.beta_tolerance
            )
            write_summary_outputs(
                args.output_dir,
                args.label,
                args.betaweights_file,
                output_source,
                marginal_likelihood,
                contributions,
            )
            print(f"Parsed {len(contributions)} complete integration points")
            print(f"Log marginal likelihood: {marginal_likelihood:.10f}")
            print(f"Results written to: {args.output_dir}")
            return 0

        if args.command == "compare":
            summaries = [parse_model_summary(path) for path in args.summary_files]
            write_comparison(args.output_dir, summaries)
            best = max(summaries, key=lambda item: item.log_marginal_likelihood)
            print(f"Compared {len(summaries)} final-network models")
            print(f"Best model: {best.model} ({best.log_marginal_likelihood:.10f})")
            print(f"Comparison written to: {args.output_dir}")
            return 0

        raise ValueError(f"unknown command: {args.command}")
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Calculate a BPP log marginal likelihood by Gaussian quadrature."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import glob
import math
from pathlib import Path
import re
import sys
from typing import Sequence


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


def parse_betaweights_file(betaweights_file: Path) -> list[BetaWeight]:
    """Read the beta and weight columns created by ``bpp --bfdriver``."""
    with betaweights_file.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = [field.strip().lower() for field in next(reader)]
        except StopIteration as exc:
            raise ValueError("the beta-weights CSV is empty") from exc

        try:
            beta_index = header.index("beta")
            weight_index = header.index("weight")
        except ValueError as exc:
            raise ValueError(
                "the beta-weights CSV must contain columns named 'beta' and 'weight'"
            ) from exc

        points: list[BetaWeight] = []
        seen_betas: list[float] = []
        for line_number, row in enumerate(reader, start=2):
            if not row or not any(field.strip() for field in row):
                continue
            if max(beta_index, weight_index) >= len(row):
                raise ValueError(f"line {line_number} is missing beta or weight")
            try:
                beta = float(row[beta_index])
                weight = float(row[weight_index])
            except ValueError as exc:
                raise ValueError(f"line {line_number} has a non-numeric beta or weight") from exc
            if not (math.isfinite(beta) and math.isfinite(weight)):
                raise ValueError(f"line {line_number} has a non-finite beta or weight")
            if not 0 <= beta <= 1:
                raise ValueError(f"line {line_number} has beta outside [0, 1]: {beta}")
            if weight <= 0:
                raise ValueError(f"line {line_number} has a non-positive weight: {weight}")
            if any(math.isclose(beta, old, rel_tol=0, abs_tol=1e-12) for old in seen_betas):
                raise ValueError(f"duplicate beta value in CSV: {beta}")
            seen_betas.append(beta)
            points.append(BetaWeight(beta, weight))

    if not points:
        raise ValueError("the beta-weights CSV contains no quadrature points")

    weight_sum = sum(point.weight for point in points)
    if not math.isclose(weight_sum, 2.0, rel_tol=1e-5, abs_tol=1e-5):
        raise ValueError(
            f"quadrature weights sum to {weight_sum:.10g}, but BPP Gauss-Legendre weights should sum to 2"
        )
    return sorted(points, key=lambda point: point.beta)


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


def read_power_posterior_files(pattern: str) -> list[PowerPosteriorResult]:
    filenames = sorted(Path(name) for name in glob.glob(pattern))
    if not filenames:
        raise ValueError(f"no files matched pattern: {pattern}")
    return [parse_power_posterior_file(filename) for filename in filenames]


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
        candidates = sorted(
            unmatched, key=lambda index: abs(points[index].beta - result.beta)
        )
        if not candidates:
            raise ValueError(
                f"more output files than quadrature points; duplicate beta near {result.beta}"
            )
        index = candidates[0]
        point = points[index]
        difference = abs(point.beta - result.beta)
        if difference > beta_tolerance:
            raise ValueError(
                f"beta {result.beta:.10g} from '{result.filename}' has no CSV match "
                f"within tolerance {beta_tolerance:g}"
            )
        unmatched.remove(index)
        value = point.weight * result.expected_log_likelihood / 2.0
        contributions.append(
            Contribution(
                result.filename,
                point.beta,
                point.weight,
                result.expected_log_likelihood,
                value,
            )
        )

    if unmatched:
        missing = ", ".join(f"{points[index].beta:.10g}" for index in sorted(unmatched))
        raise ValueError(f"missing BPP output for beta value(s): {missing}")

    contributions.sort(key=lambda item: item.beta)
    return sum(item.value for item in contributions), contributions


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Calculate a BPP log marginal likelihood from BFdriver weights and power-posterior outputs."
    )
    parser.add_argument("betaweights_file", type=Path, help="CSV generated by bpp --bfdriver")
    parser.add_argument(
        "output_pattern",
        help="quoted glob matching BPP output files, for example '*.out.*'",
    )
    parser.add_argument("output_file", type=Path, help="text report to create")
    parser.add_argument(
        "--beta-tolerance",
        type=float,
        default=1e-6,
        help="absolute tolerance when matching printed beta values (default: 1e-6)",
    )
    return parser


def write_report(
    output_file: Path, marginal_likelihood: float, contributions: Sequence[Contribution]
) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w", encoding="utf-8") as handle:
        handle.write(f"Log marginal likelihood: {marginal_likelihood:.10f}\n\n")
        handle.write("Filename\tbeta\tweight\tElnfX\tcontribution\n")
        for item in contributions:
            handle.write(
                f"{item.filename.name}\t{item.beta:.10g}\t{item.weight:.10g}\t"
                f"{item.expected_log_likelihood:.10g}\t{item.value:.10g}\n"
            )


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
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
        write_report(args.output_file, marginal_likelihood, contributions)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Parsed {len(contributions)} power-posterior runs")
    for item in contributions:
        print(
            f"{item.filename.name}: beta={item.beta:.10g}, weight={item.weight:.10g}, "
            f"ElnfX={item.expected_log_likelihood:.10g}, contribution={item.value:.10g}"
        )
    print(f"Log marginal likelihood: {marginal_likelihood:.10f}")
    print(f"Report written to: {args.output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

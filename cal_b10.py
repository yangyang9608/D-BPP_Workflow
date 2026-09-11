#!/usr/bin/env python3
"""Calculate small-interval Savage-Dickey B10 values from BPP posterior phi samples.

By default, D-BPP reports B10 at epsilon = 0.01 and 0.001 under a
Uniform(0, 1) prior for phi.  For a different phi prior, supply the prior
probability Pr(phi < epsilon) explicitly with --prior-mass.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
from pathlib import Path
import re
import sys
from typing import Iterable, Sequence


DEFAULT_EPSILONS = (0.01, 0.001)
DEFAULT_CUTOFF = 100.0
PHI_PREFIX_RE = re.compile(r"^phi[:_]", re.IGNORECASE)


@dataclass(frozen=True)
class B10Result:
    epsilon: float
    prior_mass: float
    posterior_mass: float
    count_below: int
    n_samples: int
    b10: float
    supported: bool


def read_table(file_path: Path) -> tuple[list[str], dict[str, list[str]]]:
    """Read a whitespace-delimited BPP table and reject malformed rows."""
    with file_path.open("r", encoding="utf-8") as handle:
        first_line = handle.readline().strip()
        if not first_line:
            raise ValueError("the input file is empty or has no header")

        header = first_line.split()
        if len(header) != len(set(header)):
            raise ValueError("the input header contains duplicate column names")

        data = {column: [] for column in header}
        for line_number, line in enumerate(handle, start=2):
            if not line.strip():
                continue
            values = line.split()
            if len(values) != len(header):
                raise ValueError(
                    f"line {line_number} has {len(values)} fields; expected {len(header)}"
                )
            for column, value in zip(header, values):
                data[column].append(value)

    return header, data


def is_phi_column(column_name: str) -> bool:
    return PHI_PREFIX_RE.match(column_name) is not None


def scenario_name_from_column(column_name: str) -> str:
    scenario = PHI_PREFIX_RE.sub("", column_name, count=1)
    # Current BPP headers can include numeric and symbolic mappings, for example
    # ``phi:12<-6:Z2<-Z1``. Prefer the stable symbolic suffix when present.
    return scenario.rsplit(":", maxsplit=1)[-1]


def parse_phi_samples(column_data: Sequence[str | float]) -> list[float]:
    values: list[float] = []
    for item in column_data:
        try:
            value = float(item)
        except (TypeError, ValueError) as exc:
            raise ValueError(f"non-numeric phi sample: {item!r}") from exc
        if not math.isfinite(value):
            raise ValueError(f"non-finite phi sample: {item!r}")
        if not 0 <= value <= 1:
            raise ValueError(f"phi sample outside [0, 1]: {value}")
        values.append(value)

    if not values:
        raise ValueError("the phi column contains no posterior samples")
    return values


def calculate_b10(
    column_data: Sequence[str | float],
    epsilon: float,
    prior_mass: float | None = None,
    cutoff: float = DEFAULT_CUTOFF,
) -> B10Result:
    """Calculate B10 = Pr(phi<eps) / Pr(phi<eps | X).

    If ``prior_mass`` is omitted, a Uniform(0, 1) prior is assumed and
    Pr(phi < epsilon) = epsilon.
    """
    if not 0 < epsilon < 1:
        raise ValueError("epsilon must be greater than 0 and less than 1")
    if cutoff <= 0 or not math.isfinite(cutoff):
        raise ValueError("cutoff must be a finite value greater than 0")

    if prior_mass is None:
        prior_mass = epsilon
    if not 0 < prior_mass <= 1 or not math.isfinite(prior_mass):
        raise ValueError("prior mass must be a finite value in (0, 1]")

    values = parse_phi_samples(column_data)
    count_below = sum(value < epsilon for value in values)
    posterior_mass = count_below / len(values)
    b10 = math.inf if posterior_mass == 0 else prior_mass / posterior_mass
    return B10Result(
        epsilon=epsilon,
        prior_mass=prior_mass,
        posterior_mass=posterior_mass,
        count_below=count_below,
        n_samples=len(values),
        b10=b10,
        supported=b10 >= cutoff,
    )


def format_number(value: float) -> str:
    return "Inf" if math.isinf(value) else f"{value:.10g}"


def epsilon_label(epsilon: float) -> str:
    return f"{epsilon:g}"


def normalize_epsilons(values: Iterable[float]) -> list[float]:
    result: list[float] = []
    for value in values:
        if not 0 < value < 1:
            raise ValueError(f"epsilon must be in (0, 1): {value}")
        if not any(math.isclose(value, old, rel_tol=0, abs_tol=1e-15) for old in result):
            result.append(value)
    return result


def parse_prior_mass(items: Sequence[str] | None) -> dict[float, float]:
    """Parse repeatable EPSILON=PRIOR_MASS arguments."""
    mapping: dict[float, float] = {}
    for item in items or []:
        if "=" not in item:
            raise ValueError(
                f"invalid --prior-mass value {item!r}; expected EPSILON=PRIOR_MASS"
            )
        eps_text, mass_text = item.split("=", 1)
        try:
            epsilon = float(eps_text)
            mass = float(mass_text)
        except ValueError as exc:
            raise ValueError(
                f"invalid --prior-mass value {item!r}; expected numeric EPSILON=PRIOR_MASS"
            ) from exc
        if not 0 < epsilon < 1:
            raise ValueError(f"prior-mass epsilon must be in (0, 1): {epsilon}")
        if not 0 < mass <= 1 or not math.isfinite(mass):
            raise ValueError(f"prior mass must be in (0, 1]: {mass}")
        mapping[epsilon] = mass
    return mapping


def lookup_prior_mass(mapping: dict[float, float], epsilon: float) -> float | None:
    for key, value in mapping.items():
        if math.isclose(key, epsilon, rel_tol=0, abs_tol=1e-15):
            return value
    return None


def default_details_path(output_file: Path) -> Path:
    if output_file.suffix:
        return output_file.with_name(f"{output_file.stem}.details{output_file.suffix}")
    return output_file.with_name(f"{output_file.name}.details.tsv")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Calculate small-interval Savage-Dickey B10 values for all phi columns "
            "in a BPP MCMC sample table. By default both epsilon=0.01 and 0.001 are reported."
        )
    )
    parser.add_argument("input_file", type=Path, help="BPP MCMC sample table")
    parser.add_argument("output_file", type=Path, help="wide tab-delimited summary table")
    parser.add_argument(
        "--epsilon",
        "--eps",
        dest="epsilons",
        action="append",
        type=float,
        help=(
            "epsilon value to evaluate; repeat for multiple values. "
            "If omitted, 0.01 and 0.001 are both evaluated"
        ),
    )
    parser.add_argument(
        "--cutoff",
        type=float,
        default=DEFAULT_CUTOFF,
        help=f"B10 support cutoff used for the Supported column (default: {DEFAULT_CUTOFF:g})",
    )
    parser.add_argument(
        "--prior-mass",
        "--prior_mass",
        action="append",
        metavar="EPSILON=PRIOR_MASS",
        help=(
            "override Pr(phi<epsilon) for a non-Uniform phi prior; repeat for each epsilon. "
            "Without this option a Uniform(0,1) prior is assumed"
        ),
    )
    parser.add_argument(
        "--details-file",
        type=Path,
        help="long-format details table (default: <output>.details.tsv)",
    )
    return parser


def write_outputs(
    output_file: Path,
    details_file: Path,
    rows: Sequence[tuple[str, str, dict[float, B10Result]]],
    epsilons: Sequence[float],
    cutoff: float,
) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    details_file.parent.mkdir(parents=True, exist_ok=True)

    with output_file.open("w", encoding="utf-8") as handle:
        header = ["Scenario", "PhiColumn", "NSamples"]
        for epsilon in epsilons:
            label = epsilon_label(epsilon)
            header.extend([f"B10_eps{label}", f"Supported_eps{label}"])
        handle.write("\t".join(header) + "\n")
        for scenario, column, result_map in sorted(rows, key=lambda item: item[0]):
            first = next(iter(result_map.values()))
            fields = [scenario, column, str(first.n_samples)]
            for epsilon in epsilons:
                result = result_map[epsilon]
                fields.extend([format_number(result.b10), "yes" if result.supported else "no"])
            handle.write("\t".join(fields) + "\n")

    with details_file.open("w", encoding="utf-8") as handle:
        handle.write(
            "Scenario\tPhiColumn\tEpsilon\tPriorMass\tPosteriorMass\t"
            "CountBelow\tNSamples\tB10\tCutoff\tSupported\n"
        )
        for scenario, column, result_map in sorted(rows, key=lambda item: item[0]):
            for epsilon in epsilons:
                result = result_map[epsilon]
                handle.write(
                    f"{scenario}\t{column}\t{epsilon_label(epsilon)}\t"
                    f"{format_number(result.prior_mass)}\t"
                    f"{format_number(result.posterior_mass)}\t"
                    f"{result.count_below}\t{result.n_samples}\t"
                    f"{format_number(result.b10)}\t{format_number(cutoff)}\t"
                    f"{'yes' if result.supported else 'no'}\n"
                )


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.input_file.is_file():
        print(f"ERROR: input file does not exist: {args.input_file}", file=sys.stderr)
        return 1

    try:
        epsilons = normalize_epsilons(args.epsilons or DEFAULT_EPSILONS)
        if args.cutoff <= 0 or not math.isfinite(args.cutoff):
            raise ValueError("--cutoff must be a finite value greater than 0")
        prior_mass_map = parse_prior_mass(args.prior_mass)
        for configured_epsilon in prior_mass_map:
            if not any(
                math.isclose(configured_epsilon, epsilon, rel_tol=0, abs_tol=1e-15)
                for epsilon in epsilons
            ):
                raise ValueError(
                    f"--prior-mass was supplied for epsilon={configured_epsilon:g}, "
                    "but that epsilon is not being evaluated"
                )

        header, data = read_table(args.input_file)
        phi_columns = [column for column in header if is_phi_column(column)]
        if not phi_columns:
            raise ValueError("no columns beginning with 'phi:' or 'phi_' were found")

        rows: list[tuple[str, str, dict[float, B10Result]]] = []
        for column in phi_columns:
            result_map: dict[float, B10Result] = {}
            for epsilon in epsilons:
                prior_mass = lookup_prior_mass(prior_mass_map, epsilon)
                result = calculate_b10(
                    data[column],
                    epsilon=epsilon,
                    prior_mass=prior_mass,
                    cutoff=args.cutoff,
                )
                result_map[epsilon] = result
                prior_note = (
                    "Uniform(0,1)" if prior_mass is None else f"prior mass={prior_mass:g}"
                )
                print(
                    f"{column}: epsilon={epsilon:g}; B10={format_number(result.b10)}; "
                    f"phi<epsilon: {result.count_below}/{result.n_samples} "
                    f"({result.posterior_mass:.6g}); {prior_note}; "
                    f"supported={'yes' if result.supported else 'no'}"
                )
            rows.append((scenario_name_from_column(column), column, result_map))

        details_file = args.details_file or default_details_path(args.output_file)
        write_outputs(args.output_file, details_file, rows, epsilons, args.cutoff)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Summary written to: {args.output_file}")
    print(f"Details written to: {details_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

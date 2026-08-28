#!/usr/bin/env python3
"""Calculate approximate B10 values from BPP posterior phi samples."""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import re
import sys
from typing import Sequence


DEFAULT_EPSILON = 0.001
PHI_PREFIX_RE = re.compile(r"^phi[:_]", re.IGNORECASE)


def read_table(file_path: Path) -> tuple[list[str], dict[str, list[str]]]:
    """Read a whitespace-delimited table and reject malformed rows."""
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
    # Current BPP headers include both numeric and symbolic mappings, e.g.
    # ``phi:12<-6:Z2<-Z1``. Prefer the stable symbolic suffix.
    return scenario.rsplit(":", maxsplit=1)[-1]


def calculate_b10(
    column_data: Sequence[str | float], epsilon: float = DEFAULT_EPSILON
) -> tuple[float, float, int, int]:
    """Return B10, posterior mass below epsilon, count below, and sample count.

    Under a Uniform(0, 1) prior for phi, the prior mass in [0, epsilon)
    equals epsilon. The approximation used by D-BPP is therefore
    B10 = epsilon / Pr(phi < epsilon | data).
    """
    if not 0 < epsilon < 1:
        raise ValueError("epsilon must be greater than 0 and less than 1")

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

    count_below = sum(value < epsilon for value in values)
    posterior_mass = count_below / len(values)
    b10 = math.inf if posterior_mass == 0 else epsilon / posterior_mass
    return b10, posterior_mass, count_below, len(values)


def format_number(value: float) -> str:
    return "Inf" if math.isinf(value) else f"{value:.10g}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Calculate approximate B10 values for all phi columns in a BPP MCMC table."
    )
    parser.add_argument("input_file", type=Path, help="BPP MCMC sample table")
    parser.add_argument("output_file", type=Path, help="tab-delimited output table")
    parser.add_argument(
        "--epsilon",
        "--eps",
        type=float,
        default=DEFAULT_EPSILON,
        help=f"near-zero interval boundary (default: {DEFAULT_EPSILON})",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.input_file.is_file():
        print(f"ERROR: input file does not exist: {args.input_file}", file=sys.stderr)
        return 1
    if not 0 < args.epsilon < 1:
        print("ERROR: --epsilon must be greater than 0 and less than 1", file=sys.stderr)
        return 1

    try:
        header, data = read_table(args.input_file)
        phi_columns = [column for column in header if is_phi_column(column)]
        if not phi_columns:
            raise ValueError("no columns beginning with 'phi:' or 'phi_' were found")

        results = []
        for column in phi_columns:
            b10, posterior_mass, count_below, total = calculate_b10(
                data[column], args.epsilon
            )
            results.append((scenario_name_from_column(column), b10))
            print(
                f"{column}: B10={format_number(b10)}; "
                f"phi<{args.epsilon:g}: {count_below}/{total} "
                f"({posterior_mass:.6g})"
            )

        results.sort(key=lambda item: item[0])
        args.output_file.parent.mkdir(parents=True, exist_ok=True)
        with args.output_file.open("w", encoding="utf-8") as handle:
            handle.write("Scenario\tB10\n")
            for scenario, b10 in results:
                handle.write(f"{scenario}\t{format_number(b10)}\n")
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Results written to: {args.output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

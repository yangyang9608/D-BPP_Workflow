import contextlib
import io
import math
from pathlib import Path
import tempfile
import unittest

import cal_b10


class CalculateB10Tests(unittest.TestCase):
    def test_calculates_expected_ratio_under_uniform_prior(self):
        result = cal_b10.calculate_b10(
            ["0.0005", "0.002", "0.1", "0.0001"], epsilon=0.001
        )
        self.assertAlmostEqual(result.b10, 0.002)
        self.assertAlmostEqual(result.posterior_mass, 0.5)
        self.assertEqual((result.count_below, result.n_samples), (2, 4))
        self.assertFalse(result.supported)

    def test_supports_explicit_prior_mass(self):
        result = cal_b10.calculate_b10(
            [0.001, 0.02, 0.5, 0.7], epsilon=0.01, prior_mass=0.025, cutoff=0.09
        )
        self.assertAlmostEqual(result.posterior_mass, 0.25)
        self.assertAlmostEqual(result.b10, 0.1)
        self.assertTrue(result.supported)

    def test_returns_infinity_when_no_sample_is_near_zero(self):
        result = cal_b10.calculate_b10([0.1, 0.2], epsilon=0.001)
        self.assertTrue(math.isinf(result.b10))
        self.assertEqual((result.posterior_mass, result.count_below, result.n_samples), (0.0, 0, 2))

    def test_rejects_invalid_phi_samples(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            cal_b10.calculate_b10([1.2], epsilon=0.01)
        with self.assertRaisesRegex(ValueError, "no posterior"):
            cal_b10.calculate_b10([], epsilon=0.01)

    def test_cli_defaults_to_both_epsilons_and_writes_details(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            input_file = temp / "samples.txt"
            output_file = temp / "b10.tsv"
            input_file.write_text(
                "iter phi:12<-6:Z2<-Z1 phi_Z4<-Z3\n"
                "1 0.0001 0.1\n"
                "2 0.005 0.2\n"
                "3 0.02 0.3\n"
                "4 0.2 0.4\n",
                encoding="utf-8",
            )

            with contextlib.redirect_stdout(io.StringIO()):
                status = cal_b10.main([str(input_file), str(output_file)])

            self.assertEqual(status, 0)
            text = output_file.read_text(encoding="utf-8")
            self.assertIn("B10_eps0.01", text)
            self.assertIn("B10_eps0.001", text)
            self.assertIn("Z2<-Z1", text)
            details = temp / "b10.details.tsv"
            self.assertTrue(details.is_file())
            details_text = details.read_text(encoding="utf-8")
            self.assertIn("\t0.01\t", details_text)
            self.assertIn("\t0.001\t", details_text)

    def test_cli_accepts_custom_prior_mass(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            input_file = temp / "samples.txt"
            output_file = temp / "b10.tsv"
            input_file.write_text(
                "iter phi_Z2<-Z1\n1 0.001\n2 0.02\n3 0.5\n4 0.7\n",
                encoding="utf-8",
            )
            with contextlib.redirect_stdout(io.StringIO()):
                status = cal_b10.main(
                    [
                        str(input_file),
                        str(output_file),
                        "--epsilon",
                        "0.01",
                        "--prior-mass",
                        "0.01=0.025",
                        "--cutoff",
                        "0.09",
                    ]
                )
            self.assertEqual(status, 0)
            row = output_file.read_text(encoding="utf-8").splitlines()[1].split("\t")
            self.assertEqual(row[-2:], ["0.1", "yes"])


if __name__ == "__main__":
    unittest.main()

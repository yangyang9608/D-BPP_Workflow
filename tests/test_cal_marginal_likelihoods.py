import contextlib
import io
from pathlib import Path
import tempfile
import unittest

import cal_marginal_likelihoods as marginal


class MarginalLikelihoodTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.temp = Path(self.temp_directory.name)

    def tearDown(self):
        self.temp_directory.cleanup()

    def write_betaweights(self):
        path = self.temp / "model.betaweights.csv"
        path.write_text(
            "beta,weight,ElnfX\n0.25,1.0,\n0.75,1.0,\n", encoding="utf-8"
        )
        return path

    def write_output(self, name, beta, expectation):
        path = self.temp / name
        path.write_text(
            f"run complete\nBFbeta = {beta} E_b(lnf(X)) = {expectation}\n",
            encoding="utf-8",
        )
        return path

    def test_integrates_complete_quadrature_set(self):
        points = marginal.parse_betaweights_file(self.write_betaweights())
        results = [
            marginal.parse_power_posterior_file(
                self.write_output("model.out.1", 0.2500004, -10)
            ),
            marginal.parse_power_posterior_file(
                self.write_output("model.out.2", 0.75, -2)
            ),
        ]
        value, contributions = marginal.calculate_marginal_likelihood(
            points, results
        )
        self.assertAlmostEqual(value, -6.0)
        self.assertEqual(len(contributions), 2)

    def test_rejects_missing_quadrature_point(self):
        points = marginal.parse_betaweights_file(self.write_betaweights())
        results = [
            marginal.parse_power_posterior_file(
                self.write_output("model.out.1", 0.25, -10)
            )
        ]
        with self.assertRaisesRegex(ValueError, "missing BPP output"):
            marginal.calculate_marginal_likelihood(points, results)

    def test_rejects_incomplete_weight_set(self):
        path = self.temp / "bad.csv"
        path.write_text("beta,weight\n0.25,0.5\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "sum"):
            marginal.parse_betaweights_file(path)

    def test_cli_writes_report(self):
        weights = self.write_betaweights()
        self.write_output("model.out.1", 0.25, -10)
        self.write_output("model.out.2", 0.75, -2)
        report = self.temp / "report.txt"

        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [str(weights), str(self.temp / "model.out.*"), str(report)]
            )

        self.assertEqual(status, 0)
        text = report.read_text(encoding="utf-8")
        self.assertIn("Log marginal likelihood: -6.0000000000", text)
        self.assertIn("model.out.1", text)


if __name__ == "__main__":
    unittest.main()

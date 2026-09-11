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

    def write_betaweights(self, name="model.betaweights.csv"):
        path = self.temp / name
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
        value, contributions = marginal.calculate_marginal_likelihood(points, results)
        self.assertAlmostEqual(value, -6.0)
        self.assertEqual(len(contributions), 2)

    def test_accepts_whitespace_betaweights(self):
        path = self.temp / "betaweights.txt"
        path.write_text("beta weight\n0.25 1\n0.75 1\n", encoding="utf-8")
        points = marginal.parse_betaweights_file(path)
        self.assertEqual([(p.beta, p.weight) for p in points], [(0.25, 1.0), (0.75, 1.0)])

    def test_rejects_missing_quadrature_point(self):
        points = marginal.parse_betaweights_file(self.write_betaweights())
        results = [
            marginal.parse_power_posterior_file(
                self.write_output("model.out.1", 0.25, -10)
            )
        ]
        with self.assertRaisesRegex(ValueError, "missing BPP output"):
            marginal.calculate_marginal_likelihood(points, results)

    def test_rejects_duplicate_beta_outputs(self):
        self.write_output("model.out.1", 0.25, -10)
        self.write_output("model.out.2", 0.25, -11)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            marginal.read_power_posterior_files(str(self.temp / "model.out.*"))

    def test_summarize_writes_separate_result_files(self):
        weights = self.write_betaweights()
        self.write_output("model.out.1", 0.25, -10)
        self.write_output("model.out.2", 0.75, -2)
        result_dir = self.temp / "results"

        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [
                    "summarize",
                    str(weights),
                    str(self.temp / "model.out.*"),
                    "--label",
                    "Tree1_final_network",
                    "--output-dir",
                    str(result_dir),
                ]
            )

        self.assertEqual(status, 0)
        self.assertTrue((result_dir / "integration_points.tsv").is_file())
        self.assertTrue((result_dir / "marginal_likelihood.tsv").is_file())
        self.assertTrue((result_dir / "marginal_likelihood_report.txt").is_file())
        self.assertIn(
            "Tree1_final_network\t-6.0000000000",
            (result_dir / "marginal_likelihood.tsv").read_text(encoding="utf-8"),
        )


    def test_summarize_reads_recorded_screen_logs_from_run_manifest(self):
        weights = self.write_betaweights()
        run_dir = self.temp / "run_records"
        logs_dir = run_dir / "logs"
        logs_dir.mkdir(parents=True)
        log1 = logs_dir / "001_model.b01.log"
        log2 = logs_dir / "002_model.b02.log"
        log1.write_text("BFbeta = 0.25 E_b(lnf(X)) = -10\n", encoding="utf-8")
        log2.write_text("BFbeta = 0.75 E_b(lnf(X)) = -2\n", encoding="utf-8")
        (run_dir / "run_manifest.tsv").write_text(
            "control_file\tlog_file\treturn_code\tstatus\telapsed_seconds\tstarted_utc\tfinished_utc\n"
            f"a.ctl\t{log1}\t0\tOK\t1\tstart\tfinish\n"
            f"b.ctl\t{log2}\t0\tOK\t1\tstart\tfinish\n",
            encoding="utf-8",
        )
        result_dir = self.temp / "results_from_manifest"
        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [
                    "summarize",
                    str(weights),
                    "--run-dir",
                    str(run_dir),
                    "--label",
                    "Tree1_final_network",
                    "--output-dir",
                    str(result_dir),
                ]
            )
        self.assertEqual(status, 0)
        summary = (result_dir / "marginal_likelihood.tsv").read_text(encoding="utf-8")
        self.assertIn("Tree1_final_network\t-6.0000000000", summary)
        self.assertIn("run_manifest:", summary)

    def test_compare_ranks_models(self):
        a = self.temp / "a.tsv"
        b = self.temp / "b.tsv"
        header = "model\tlog_marginal_likelihood\tn_points\tbetaweights_file\toutput_pattern\n"
        a.write_text(header + "A\t-100.0\t16\ta\tx\n", encoding="utf-8")
        b.write_text(header + "B\t-95.0\t16\tb\ty\n", encoding="utf-8")
        output_dir = self.temp / "comparison"
        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                ["compare", str(a), str(b), "--output-dir", str(output_dir)]
            )
        self.assertEqual(status, 0)
        rows = (output_dir / "model_comparison.tsv").read_text(encoding="utf-8").splitlines()
        self.assertTrue(rows[1].startswith("1\tB\t"))
        self.assertIn("\t5.0000000000\t5.0000000000\t", rows[2])

    def test_prepare_records_bfdriver_outputs(self):
        fake_bpp = self.temp / "bpp"
        fake_bpp.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "[[ \"$1\" == \"--bfdriver\" ]]\n"
            "ctl=\"$2\"\n"
            "stem=${ctl%.ctl}\n"
            "printf 'seed = -1\n' > \"${stem}.b01.ctl\"\n"
            "printf 'seed = -1\n' > \"${stem}.b02.ctl\"\n"
            "printf 'beta,weight\n0.25,1\n0.75,1\n' > \"${ctl}.betaweights.csv\"\n"
            "echo prepared\n",
            encoding="utf-8",
        )
        fake_bpp.chmod(0o755)
        ctl = self.temp / "model.ctl"
        ctl.write_text("seed = -1\n", encoding="utf-8")
        run_dir = self.temp / "prepare_records"
        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [
                    "prepare", str(ctl), "--points", "2",
                    "--bpp", str(fake_bpp), "--run-dir", str(run_dir),
                ]
            )
        self.assertEqual(status, 0)
        self.assertTrue((run_dir / "bfdriver.log").is_file())
        manifest = (run_dir / "bfdriver_manifest.tsv").read_text(encoding="utf-8")
        self.assertIn("generated_control", manifest)
        self.assertIn("betaweights_candidate", manifest)

    def test_run_creates_execution_manifest_and_logs(self):
        fake_bpp = self.temp / "bpp"
        fake_bpp.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "[[ \"$1\" == \"--cfile\" ]]\n"
            "echo \"running $2\"\n",
            encoding="utf-8",
        )
        fake_bpp.chmod(0o755)
        for index in (1, 2):
            (self.temp / f"model.b{index:02d}.ctl").write_text("seed = -1\n", encoding="utf-8")
        run_dir = self.temp / "run_records"
        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [
                    "run",
                    str(self.temp / "model.b*.ctl"),
                    "--bpp",
                    str(fake_bpp),
                    "--run-dir",
                    str(run_dir),
                ]
            )
        self.assertEqual(status, 0)
        self.assertTrue((run_dir / "run_manifest.tsv").is_file())
        self.assertEqual(len(list((run_dir / "logs").glob("*.log"))), 2)

    def test_legacy_cli_still_works(self):
        weights = self.write_betaweights()
        self.write_output("model.out.1", 0.25, -10)
        self.write_output("model.out.2", 0.75, -2)
        report = self.temp / "legacy.txt"
        with contextlib.redirect_stdout(io.StringIO()):
            status = marginal.main(
                [str(weights), str(self.temp / "model.out.*"), str(report)]
            )
        self.assertEqual(status, 0)
        self.assertIn("Log marginal likelihood: -6.0000000000", report.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

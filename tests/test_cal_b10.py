import contextlib
import io
import math
from pathlib import Path
import tempfile
import unittest

import cal_b10


class CalculateB10Tests(unittest.TestCase):
    def test_calculates_expected_ratio(self):
        b10, posterior, count, total = cal_b10.calculate_b10(
            ["0.0005", "0.002", "0.1", "0.0001"], epsilon=0.001
        )
        self.assertAlmostEqual(b10, 0.002)
        self.assertAlmostEqual(posterior, 0.5)
        self.assertEqual((count, total), (2, 4))

    def test_returns_infinity_when_no_sample_is_near_zero(self):
        b10, posterior, count, total = cal_b10.calculate_b10(
            [0.1, 0.2], epsilon=0.001
        )
        self.assertTrue(math.isinf(b10))
        self.assertEqual((posterior, count, total), (0.0, 0, 2))

    def test_rejects_invalid_phi_samples(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            cal_b10.calculate_b10([1.2])
        with self.assertRaisesRegex(ValueError, "no posterior"):
            cal_b10.calculate_b10([])

    def test_cli_supports_colon_and_underscore_headers(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            input_file = temp / "samples.txt"
            output_file = temp / "b10.tsv"
            input_file.write_text(
                "iter phi:12<-6:Z2<-Z1 phi_Z4<-Z3\n"
                "1 0.0001 0.1\n"
                "2 0.1 0.2\n",
                encoding="utf-8",
            )

            with contextlib.redirect_stdout(io.StringIO()):
                status = cal_b10.main(
                    [str(input_file), str(output_file), "--epsilon", "0.001"]
                )

            self.assertEqual(status, 0)
            self.assertEqual(
                output_file.read_text(encoding="utf-8"),
                "Scenario\tB10\nZ2<-Z1\t0.002\nZ4<-Z3\tInf\n",
            )


if __name__ == "__main__":
    unittest.main()

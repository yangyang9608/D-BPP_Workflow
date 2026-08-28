import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]


class ShellWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.temp = Path(self.temp_directory.name)
        self.fake_bin = self.temp / "bin"
        self.fake_bin.mkdir()
        self.environment = os.environ.copy()
        self.environment["PATH"] = f"{self.fake_bin}:{self.environment['PATH']}"

    def tearDown(self):
        self.temp_directory.cleanup()

    def make_executable(self, name, content):
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")
        path.chmod(0o755)
        return path

    def run_script(self, script, arguments):
        return subprocess.run(
            ["bash", str(REPOSITORY / script), *map(str, arguments)],
            cwd=self.temp,
            env=self.environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def install_d_step_mocks(self, include_snp_sites=False):
        self.make_executable(
            "nw_display",
            """
            #!/usr/bin/env bash
            cat >/dev/null
            echo valid
            """,
        )
        self.make_executable(
            "Dsuite",
            """
            #!/usr/bin/env bash
            set -eu
            prefix=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -o) prefix="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -n "$prefix" ]]
            mkdir -p "$(dirname "$prefix")"
            printf 'P1\tP2\tP3\tDstatistic\tZ-score\tp-value\tf4-ratio\tBBAA\tABBA\tBABA\n' > "${prefix}_tree.txt"
            printf 'A\tB\tC\t0.6\t4.0\t0.001\t0.2\t10\t8\t2\n' >> "${prefix}_tree.txt"
            """,
        )
        if include_snp_sites:
            self.make_executable(
                "snp-sites",
                """
                #!/usr/bin/env bash
                set -eu
                output=""
                input=""
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        -v) shift ;;
                        -o) output="$2"; shift 2 ;;
                        *) input="$1"; shift ;;
                    esac
                done
                cp "$input" "$CAPTURE_FASTA"
                printf '##fileformat=VCFv4.2\n' > "$output"
                printf '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ta\tb\tc\to\n' >> "$output"
                printf '1\t1\t.\tA\tG\t.\tPASS\t.\tGT\t0\t1\t0\t0\n' >> "$output"
                """,
            )

    def write_d_inputs(self):
        imap = self.temp / "test.imap"
        imap.write_text("a\tA\nb\tB\nc\tC\no\tOutgroup\n", encoding="utf-8")
        trees = self.temp / "test.treelist"
        trees.write_text("((A,B),C);\n", encoding="utf-8")
        return imap, trees

    def test_d_step_filters_and_calculates_dp(self):
        self.install_d_step_mocks()
        imap, trees = self.write_d_inputs()
        vcf = self.temp / "test.vcf"
        vcf.write_text("##fileformat=VCFv4.2\n", encoding="utf-8")
        prefix = self.temp / "d" / "Sig-D"

        result = self.run_script(
            "D-step.sh",
            [
                "--vcf_file",
                vcf,
                "--imap",
                imap,
                "--treelist",
                trees,
                "--prefix",
                prefix,
            ],
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        rows = (self.temp / "d" / "Sig-D-Tree1.sig-triples").read_text(
            encoding="utf-8"
        ).splitlines()
        values = rows[1].split("\t")
        self.assertAlmostEqual(float(values[-2]), 0.3)
        self.assertAlmostEqual(float(values[-1]), 0.001)

    def test_d_step_fasta_concatenation_has_no_grep_separators(self):
        self.install_d_step_mocks(include_snp_sites=True)
        imap, trees = self.write_d_inputs()
        fasta_dir = self.temp / "fasta"
        fasta_dir.mkdir()
        (fasta_dir / "locus1.fa").write_text(
            ">a\nAA\n>b\nCC\n>c\nGG\n>o\nTT\n", encoding="utf-8"
        )
        (fasta_dir / "locus2.fa").write_text(
            ">a\nAC\n>b\nCG\n>c\nGT\n>o\nTA\n", encoding="utf-8"
        )
        captured = self.temp / "concatenated.fa"
        self.environment["CAPTURE_FASTA"] = str(captured)

        result = self.run_script(
            "D-step.sh",
            [
                "--fasta_dir",
                fasta_dir,
                "--imap",
                imap,
                "--treelist",
                trees,
                "--prefix",
                self.temp / "d" / "Sig-D",
            ],
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        text = captured.read_text(encoding="utf-8")
        self.assertNotIn("\n--\n", text)
        records = {}
        current = None
        for line in text.splitlines():
            if line.startswith(">"):
                current = line[1:]
                records[current] = ""
            else:
                records[current] += line
        self.assertEqual(
            records, {"a": "AAAC", "b": "CCCG", "c": "GGGT", "o": "TTTA"}
        )

    def install_bpp_step_mocks(self):
        self.make_executable(
            "nw_display",
            """
            #!/usr/bin/env bash
            cat >/dev/null
            echo valid
            """,
        )
        self.make_executable(
            "nw_clade",
            """
            #!/usr/bin/env bash
            cat
            """,
        )
        self.make_executable(
            "nw_labels",
            """
            #!/usr/bin/env bash
            input=$(cat)
            grep -oE 'Ghost[0-9]+|N[0-9]+' <<< "$input" || true
            """,
        )
        self.make_executable(
            "nw_prune",
            """
            #!/usr/bin/env bash
            cat
            """,
        )
        self.make_executable(
            "bpp",
            """
            #!/usr/bin/env bash
            if [[ "${1-}" == "--msci-create" ]]; then
                echo '((A,B),C);'
                exit 0
            fi
            exit 2
            """,
        )

    def write_bpp_inputs(self):
        imap = self.temp / "test.imap"
        imap.write_text("a\tA\nb\tB\nc\tC\no\tOutgroup\n", encoding="utf-8")
        tree = self.temp / "test.tree"
        tree.write_text("((A,B),C);\n", encoding="utf-8")
        dstat = self.temp / "test.sig-triples"
        dstat.write_text(
            "P1\tP2\tP3\tDstatistic\tZ-score\tp-value\tf4-ratio\tBBAA\tABBA\tBABA\tDp\tadjusted_p_value\n"
            "A\tB\tC\t0.6\t4\t0.001\t0.2\t10\t8\t2\t0.3\t0.001\n",
            encoding="utf-8",
        )
        phylip = self.temp / "test.phy"
        phylip.write_text(
            " 3 4\nA^a  AAAA\nB^b  CCCC\nC^c  GGGG\n", encoding="utf-8"
        )
        return imap, tree, dstat, phylip

    def test_bpp_control_phase_and_followup_imap(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp"
        round1 = output_dir / "round1"

        first = self.run_script(
            "BPP-step.sh",
            [
                "--phylip_file",
                phylip,
                "--imap",
                imap,
                "--tree",
                tree,
                "--dstat",
                dstat,
                "--prefix",
                round1,
            ],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)

        bpp_imap = output_dir / "BPP.imap"
        expected_imap = "a\tA\nb\tB\nc\tC\n"
        self.assertEqual(bpp_imap.read_text(encoding="utf-8"), expected_imap)
        control = (output_dir / "round1.ctl").read_text(encoding="utf-8")
        phase_match = re.search(r"^\s*phase\s*=\s*(.*?)\s+\*", control, re.MULTILINE)
        self.assertIsNotNone(phase_match)
        self.assertEqual(phase_match.group(1).split(), ["0", "0", "0", "0"])

        introgression = (output_dir / "round1.introgression").read_text(
            encoding="utf-8"
        )
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        self.assertEqual(len(labels), 3)
        mcmc = output_dir / "round1.mcmc.txt"
        phi_headers = [
            f"phi:{12 + index}<-{6 + index}:{label}"
            for index, label in enumerate(labels)
        ]
        mcmc.write_text(
            "\t".join(["iter", *phi_headers])
            + "\n"
            + "\t".join(["1", *("0" for _ in labels)])
            + "\n"
            + "\t".join(["2", *("0" for _ in labels)])
            + "\n",
            encoding="utf-8",
        )

        second = self.run_script(
            "BPP-step.sh",
            [
                "--phylip_file",
                phylip,
                "--imap",
                imap,
                "--tree",
                tree,
                "--dstat",
                dstat,
                "--prefix",
                output_dir / "round2",
                "--last_step",
                round1,
                "--skip_validation",
                "--eps",
                "0.001",
            ],
        )
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertIn("Workflow complete", second.stderr)
        self.assertEqual(bpp_imap.read_text(encoding="utf-8"), expected_imap)


if __name__ == "__main__":
    unittest.main()

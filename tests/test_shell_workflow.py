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
        # Tests must not inherit installer/version overrides from the user's
        # interactive shell or from a previously activated D-BPP environment.
        for key in (
            "BPP_VERSION",
            "DSUITE_COMMIT",
            "DBPP_EXPECTED_BPP_VERSION",
            "DBPP_EXPECTED_DSUITE_COMMIT",
            "DBPP_EXTERNAL_INSTALL_MODE",
            "DBPP_BUILD_JOBS",
            "DBPP_NETWORK_RETRIES",
            "DBPP_NETWORK_RETRY_DELAY",
            "FAKE_LATEST_DSUITE_COMMIT",
        ):
            self.environment.pop(key, None)
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

    def install_external_installer_mocks(self):
        self.make_executable(
            "uname",
            """
            #!/usr/bin/env bash
            case "${1-}" in
                -s) echo Linux ;;
                -m) echo x86_64 ;;
                *) echo Linux ;;
            esac
            """,
        )
        self.make_executable(
            "wget",
            """
            #!/usr/bin/env bash
            set -eu
            if [[ "${1-}" == "-qO-" ]]; then
                echo '{"tag_name":"v9.9.9"}'
                exit 0
            fi
            output=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -O) output="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -n "$output" ]]
            : > "$output"
            """,
        )
        self.make_executable(
            "tar",
            """
            #!/usr/bin/env bash
            set -eu

            # install_external.sh first verifies the downloaded archive with
            # `tar -tzf` and later extracts it with `tar -xzf ... -C ...`.
            # The mock must implement both code paths explicitly; otherwise a
            # non-root CI runner can fail while accidentally passing as root.
            if [[ "${1-}" == "-tzf" ]]; then
                [[ -n "${2-}" ]]
                exit 0
            fi

            archive=""
            dest=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -xzf) archive="$2"; shift 2 ;;
                    -C) dest="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -n "$archive" ]]
            [[ -n "$dest" ]]
            base=$(basename "$archive" .tar.gz)
            mkdir -p "$dest/$base/bin"
            version=${base#bpp-}
            version=${version%-linux-x86_64}
            cat > "$dest/$base/bin/bpp" <<BPP
            #!/usr/bin/env bash
            echo "bpp v${version}_linux_x86_64, test build"
            BPP
            chmod +x "$dest/$base/bin/bpp"
            """,
        )
        self.make_executable(
            "git",
            """
            #!/usr/bin/env bash
            set -eu
            latest="${FAKE_LATEST_DSUITE_COMMIT:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
            if [[ "${1-}" == "ls-remote" ]]; then
                printf '%s\tHEAD\n' "$latest"
                exit 0
            fi
            if [[ "${1-}" == "clone" ]]; then
                dir="$3"
                mkdir -p "$dir/.git"
                exit 0
            fi
            if [[ "${1-}" == "-C" ]]; then
                dir="$2"
                shift 2
                case "${1-}" in
                    fetch) exit 0 ;;
                    checkout)
                        commit="${3-}"
                        printf '%s\n' "$commit" > "$dir/.fake_commit"
                        exit 0
                        ;;
                    rev-parse)
                        if [[ "${2-}" == "HEAD" ]]; then
                            cat "$dir/.fake_commit"
                            exit 0
                        fi
                        ;;
                esac
            fi
            exit 0
            """,
        )
        self.make_executable(
            "make",
            """
            #!/usr/bin/env bash
            set -eu
            dir="."
            if [[ "${1-}" == "-C" ]]; then
                dir="$2"
                shift 2
            fi
            if [[ "${1-}" == "clean" ]]; then
                rm -rf "$dir/Build"
                exit 0
            fi
            mkdir -p "$dir/Build"
            cat > "$dir/Build/Dsuite" <<'DSUITE'
            #!/usr/bin/env bash
            echo "Program: Dsuite"
            echo "Version: 0.5 r58"
            DSUITE
            chmod +x "$dir/Build/Dsuite"
            """,
        )
        self.make_executable("g++", "#!/usr/bin/env bash\nexit 0\n")

    def prepare_fake_conda_prefix(self):
        prefix = self.temp / "conda"
        (prefix / "bin").mkdir(parents=True)
        self.environment["CONDA_PREFIX"] = str(prefix)
        self.environment["PATH"] = (
            f"{self.fake_bin}:{prefix / 'bin'}:{os.environ['PATH']}"
        )
        return prefix

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
            printf 'P1\tP2\tP3\tDstatistic\tZ-score\tp-value\tf4-ratio\tclustering_sensitive\tclustering_robust\tBBAA\tABBA\tBABA\n' > "${prefix}_tree.txt"
            printf 'A\tB\tC\t0.6\t4.0\t0.001\t0.2\t0.3\t0.9\t10\t8\t2\n' >> "${prefix}_tree.txt"
            printf 'A\tB\tC\t0.1\t4.0\t0.001\t0.2\t0.4\t0.8\t100\t50\t40\n' >> "${prefix}_tree.txt"
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
        self.assertEqual(len(rows), 3)
        values = rows[1].split("\t")
        self.assertAlmostEqual(float(values[-2]), 0.3)
        self.assertAlmostEqual(float(values[-1]), 0.001)
        second_values = rows[2].split("\t")
        self.assertLess(float(second_values[-2]), float(values[-2]))

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

    def test_d_step_fasta_headers_with_descriptions_are_concatenated(self):
        self.install_d_step_mocks(include_snp_sites=True)
        imap, trees = self.write_d_inputs()
        fasta_dir = self.temp / "fasta_descriptions"
        fasta_dir.mkdir()
        (fasta_dir / "locus1.fa").write_text(
            ">a description one\nAA\n>b another description\nCC\n"
            ">c third sample\nGG\n>o outgroup sequence\nTT\n",
            encoding="utf-8",
        )
        (fasta_dir / "locus2.fa").write_text(
            ">a second locus\nAC\n>b second locus\nCG\n"
            ">c second locus\nGT\n>o second locus\nTA\n",
            encoding="utf-8",
        )
        captured = self.temp / "concatenated_descriptions.fa"
        self.environment["CAPTURE_FASTA"] = str(captured)

        result = self.run_script(
            "D-step.sh",
            [
                "--fasta_dir", fasta_dir,
                "--imap", imap,
                "--treelist", trees,
                "--prefix", self.temp / "d_desc" / "Sig-D",
            ],
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        records = {}
        current = None
        for line in captured.read_text(encoding="utf-8").splitlines():
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
        self.make_executable(
            "nw_prune",
            """
            #!/usr/bin/env bash
            set -eu
            input=$(cat)
            if [[ "${2-}" == "Ghost1" ]]; then
                inner=${input#"(Ghost1,"}
                inner=${inner%")N3;"}
                printf '(%s)N3;\n' "$inner"
            else
                printf '%s\n' "$input"
            fi
            """,
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
            ],
        )
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertIn("B10 settings: epsilon=0.01", second.stderr)
        self.assertIn("Workflow complete", second.stderr)
        self.assertIn("Species tree only (no supported introgression events)", second.stderr)
        self.assertTrue((output_dir / "final.ctl").is_file())
        self.assertTrue((output_dir / "final.msci").is_file())
        self.assertTrue((output_dir / "final.introgression").is_file())
        final_introgression = (output_dir / "final.introgression").read_text(encoding="utf-8")
        self.assertNotIn("<--", final_introgression)
        final_msci = (output_dir / "final.msci").read_text(encoding="utf-8")
        self.assertNotIn("Ghost", final_msci)
        self.assertIn("tree ((A,B)N1,C)N2;", final_msci)
        self.assertEqual(bpp_imap.read_text(encoding="utf-8"), expected_imap)

    def test_bpp_step_writes_reduced_completed_model_as_final(self):
        self.install_bpp_step_mocks()
        # Use slightly more realistic Newick mocks for this regression test so
        # the supported C->B event is recognized as explaining A,B,C.
        self.make_executable(
            "nw_clade",
            """
            #!/usr/bin/env bash
            set -eu
            input=$(cat)
            shift  # '-'
            case "$*" in
                "A B C") echo '((A,B)N1,C)N2;' ;;
                "A") echo 'A;' ;;
                "B") echo 'B;' ;;
                "C") echo 'C;' ;;
                *) printf '%s\n' "$input" ;;
            esac
            """,
        )
        self.make_executable(
            "nw_labels",
            """
            #!/usr/bin/env bash
            set -eu
            input=$(cat)
            if [[ " $* " == *" -I "* ]]; then
                grep -oE 'Ghost[0-9]+|[ABC]' <<< "$input" || true
            else
                grep -oE 'Ghost[0-9]+|N[0-9]+' <<< "$input" || true
            fi
            """,
        )
        # Reproduce the real nw_prune behavior seen on the clean server: it
        # removes Ghost1 but leaves the wrapper N3 as a unary root.
        self.make_executable(
            "nw_prune",
            """
            #!/usr/bin/env bash
            set -eu
            input=$(cat)
            if [[ "${2-}" == "Ghost1" ]]; then
                inner=${input#"(Ghost1,"}
                inner=${inner%")N3;"}
                printf '(%s)N3;\n' "$inner"
            else
                printf '%s\n' "$input"
            fi
            """,
        )
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp_final"
        round1 = output_dir / "round1"

        first = self.run_script(
            "BPP-step.sh",
            [
                "--phylip_file", phylip,
                "--imap", imap,
                "--tree", tree,
                "--dstat", dstat,
                "--prefix", round1,
            ],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)

        introgression = (output_dir / "round1.introgression").read_text(
            encoding="utf-8"
        )
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        self.assertEqual(len(labels), 3)

        # Keep only one of the three newly tested events away from phi=0.
        # The other two concentrate below epsilon and are removed.  The one
        # supported event explains the sole A,B,C triple, so the search ends
        # and a reduced final model should be written as final.*, not round2.*.
        phi_headers = [
            f"phi:{12 + index}<-{6 + index}:{label}"
            for index, label in enumerate(labels)
        ]
        mcmc = output_dir / "round1.mcmc.txt"
        rows = []
        for generation in range(1, 11):
            rows.append("\t".join([str(generation), "0", "0.5", "0"]))
        mcmc.write_text(
            "\t".join(["iter", *phi_headers]) + "\n" + "\n".join(rows) + "\n",
            encoding="utf-8",
        )

        second = self.run_script(
            "BPP-step.sh",
            [
                "--phylip_file", phylip,
                "--imap", imap,
                "--tree", tree,
                "--dstat", dstat,
                "--prefix", output_dir / "round2",
                "--last_step", round1,
                "--skip_validation",
                "--eps", "0.01",
                "--b10_cutoff", "100",
            ],
        )
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertIn(
            "Workflow complete: no significant D-statistic triples remain in the candidate queue",
            second.stderr,
        )
        self.assertIn("Final BPP control file:", second.stderr)
        self.assertIn("The network-search stage is complete.", second.stderr)
        self.assertIn("To estimate parameters under the reduced final model", second.stderr)
        self.assertTrue((output_dir / "final.ctl").is_file())
        self.assertTrue((output_dir / "final.msci").is_file())
        self.assertTrue((output_dir / "final.introgression").is_file())
        final_msci = (output_dir / "final.msci").read_text(encoding="utf-8")
        self.assertIn("tree ((A,B)N1,C)N2;", final_msci)
        self.assertNotIn("(((A,B)N1,C)N2)N3;", final_msci)
        final_ctl = (output_dir / "final.ctl").read_text(encoding="utf-8")
        self.assertRegex(final_ctl, r"(?m)^\s*species&tree\s*=\s*3 A B C$")
        self.assertNotRegex(final_ctl, r"(?m)^\s*N3\s*$")
        self.assertFalse((output_dir / "round2.ctl").exists())
        self.assertFalse((output_dir / "round2.msci").exists())

    def test_bpp_step_continues_after_no_new_event_is_supported(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        dstat.write_text(
            "P1\tP2\tP3\tDstatistic\tZ-score\tp-value\tf4-ratio\tBBAA\tABBA\tBABA\tDp\tadjusted_p_value\n"
            "A\tB\tC\t0.6\t4\t0.001\t0.2\t10\t8\t2\t0.3\t0.001\n"
            "A\tC\tB\t0.5\t4\t0.002\t0.2\t10\t7\t3\t0.2\t0.002\n",
            encoding="utf-8",
        )
        output_dir = self.temp / "bpp_continue"
        round1 = output_dir / "round1"

        first = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", round1],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        state1 = (output_dir / "round1.triple-state.tsv").read_text(encoding="utf-8")
        self.assertIn("A\tB\tC\tcandidate", state1)
        self.assertIn("A\tC\tB\tpending", state1)

        introgression1 = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        labels1 = re.findall(r":\s*(Z\S+)\s*$", introgression1, re.MULTILINE)
        headers1 = [f"phi:{12 + i}<-{6 + i}:{label}" for i, label in enumerate(labels1)]
        (output_dir / "round1.mcmc.txt").write_text(
            "\t".join(["iter", *headers1]) + "\n"
            + "\t".join(["1", *("0" for _ in labels1)]) + "\n",
            encoding="utf-8",
        )

        second = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round2",
             "--last_step", round1, "--skip_validation"],
        )
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertIn("recorded as tested", second.stderr)
        self.assertIn("Next triple to consider: A,C,B", second.stderr)
        self.assertTrue((output_dir / "round2.ctl").is_file())
        self.assertFalse((output_dir / "final.ctl").exists())
        state2 = (output_dir / "round2.triple-state.tsv").read_text(encoding="utf-8")
        self.assertIn("A\tB\tC\ttested", state2)
        self.assertIn("A\tC\tB\tcandidate", state2)

        introgression2 = (output_dir / "round2.introgression").read_text(encoding="utf-8")
        labels2 = re.findall(r":\s*(Z\S+)\s*$", introgression2, re.MULTILINE)
        headers2 = [f"phi:{12 + i}<-{6 + i}:{label}" for i, label in enumerate(labels2)]
        (output_dir / "round2.mcmc.txt").write_text(
            "\t".join(["iter", *headers2]) + "\n"
            + "\t".join(["1", *("0" for _ in labels2)]) + "\n",
            encoding="utf-8",
        )

        third = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round3",
             "--last_step", output_dir / "round2", "--skip_validation"],
        )
        self.assertEqual(third.returncode, 0, third.stderr + third.stdout)
        self.assertIn("no significant D-statistic triples remain in the candidate queue", third.stderr)
        final_state = (output_dir / "final.triple-state.tsv").read_text(encoding="utf-8")
        self.assertIn("A\tB\tC\ttested", final_state)
        self.assertIn("A\tC\tB\ttested", final_state)
        self.assertTrue((output_dir / "final.ctl").is_file())

    def test_bpp_step_carries_supported_network_forward_after_no_new_support_round(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        dstat.write_text(
            "P1\tP2\tP3\tDstatistic\tZ-score\tp-value\tf4-ratio\tBBAA\tABBA\tBABA\tDp\tadjusted_p_value\n"
            "A\tB\tC\t0.6\t4\t0.001\t0.2\t10\t8\t2\t0.3\t0.001\n"
            "A\tC\tB\t0.5\t4\t0.002\t0.2\t10\t7\t3\t0.2\t0.002\n"
            "B\tA\tC\t0.4\t4\t0.003\t0.2\t10\t6\t4\t0.1\t0.003\n",
            encoding="utf-8",
        )
        output_dir = self.temp / "bpp_cumulative"
        round1 = output_dir / "round1"

        first = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", round1],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)

        intro1 = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        pairs1 = re.findall(r"^\s*(.+?):\s*(Z\S+)\s*$", intro1, re.MULTILINE)
        self.assertEqual(len(pairs1), 3)
        # Retain one sampled-lineage event from round 1; the other two new
        # events are deliberately unsupported.
        supported_event = pairs1[1][0]
        headers1 = [f"phi:{12+i}<-{6+i}:{label}" for i, (_, label) in enumerate(pairs1)]
        values1 = ["0.5" if event == supported_event else "0" for event, _ in pairs1]
        (output_dir / "round1.mcmc.txt").write_text(
            "\t".join(["iter", *headers1]) + "\n"
            + "\t".join(["1", *values1]) + "\n",
            encoding="utf-8",
        )

        second = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round2",
             "--last_step", round1, "--skip_validation"],
        )
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertIn("Next triple to consider: A,C,B", second.stderr)
        self.assertIn("carrying forward all 1 directed introgression event(s)", second.stderr)

        intro2 = (output_dir / "round2.introgression").read_text(encoding="utf-8")
        pairs2 = re.findall(r"^\s*(.+?):\s*(Z\S+)\s*$", intro2, re.MULTILINE)
        self.assertEqual(len(pairs2), 4)
        self.assertIn(supported_event, [event for event, _ in pairs2])

        # In round 2 the previously supported event remains supported, while
        # all three events newly added for A,C,B fail the cutoff.
        headers2 = [f"phi:{22+i}<-{16+i}:{label}" for i, (_, label) in enumerate(pairs2)]
        # The first mapping is the carried-forward event; the following three
        # mappings are the candidates introduced for the current triple. Keep
        # only the carried-forward event supported, even if a newly proposed
        # event happens to have the same branch-level description.
        values2 = ["0.5" if i == 0 else "0" for i, _ in enumerate(pairs2)]
        (output_dir / "round2.mcmc.txt").write_text(
            "\t".join(["iter", *headers2]) + "\n"
            + "\t".join(["1", *values2]) + "\n",
            encoding="utf-8",
        )

        third = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round3",
             "--last_step", output_dir / "round2", "--skip_validation"],
        )
        self.assertEqual(third.returncode, 0, third.stderr + third.stdout)
        self.assertIn("None of the three events added for triple A,C,B passed the B10 cutoff", third.stderr)
        self.assertIn("Next triple to consider: B,A,C", third.stderr)
        self.assertIn("carrying forward all 1 directed introgression event(s)", third.stderr)
        self.assertTrue((output_dir / "round3.ctl").is_file())
        self.assertFalse((output_dir / "final.ctl").exists())

        intro3 = (output_dir / "round3.introgression").read_text(encoding="utf-8")
        pairs3 = re.findall(r"^\s*(.+?):\s*(Z\S+)\s*$", intro3, re.MULTILINE)
        self.assertEqual(len(pairs3), 4)
        self.assertIn(supported_event, [event for event, _ in pairs3])
        state3 = (output_dir / "round3.triple-state.tsv").read_text(encoding="utf-8")
        self.assertIn("A\tB\tC\ttested", state3)
        self.assertIn("A\tC\tB\ttested", state3)
        self.assertIn("B\tA\tC\tcandidate", state3)

    def test_bpp_step_rejects_missing_phi_column_for_introgression_event(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp_missing_phi"
        round1 = output_dir / "round1"
        first = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", round1],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        introgression = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        self.assertEqual(len(labels), 3)
        # Deliberately omit two expected phi columns.
        (output_dir / "round1.mcmc.txt").write_text(
            f"iter\tphi:12<-6:{labels[0]}\n1\t0.5\n",
            encoding="utf-8",
        )
        second = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round2",
             "--last_step", round1, "--skip_validation"],
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("has no matching phi column", second.stderr)

    def test_bpp_step_rejects_phi_outside_unit_interval(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp_bad_phi"
        round1 = output_dir / "round1"
        first = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", round1],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        introgression = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        headers = [f"phi:{12 + i}<-{6 + i}:{label}" for i, label in enumerate(labels)]
        (output_dir / "round1.mcmc.txt").write_text(
            "\t".join(["iter", *headers]) + "\n1\t0.2\t2\t0.3\n",
            encoding="utf-8",
        )
        second = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round2",
             "--last_step", round1, "--skip_validation"],
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("outside [0,1]", second.stderr)

    def test_bpp_step_rejects_malformed_mcmc_row_width(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp_bad_width"
        round1 = output_dir / "round1"
        first = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", round1],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        introgression = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        headers = [f"phi:{12 + i}<-{6 + i}:{label}" for i, label in enumerate(labels)]
        (output_dir / "round1.mcmc.txt").write_text(
            "\t".join(["iter", *headers]) + "\n1\t0.2\t0.3\n",
            encoding="utf-8",
        )
        second = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", output_dir / "round2",
             "--last_step", round1, "--skip_validation"],
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("fields; expected", second.stderr)

    def test_bpp_step_skips_fbranch_subset_enumeration_by_default(self):
        self.install_bpp_step_mocks()
        marker = self.temp / "fbranch_called"
        self.environment["FBRANCH_MARKER"] = str(marker)
        self.make_executable(
            "nw_clade",
            """
            #!/usr/bin/env bash
            if [[ "${1-}" == "-m" ]]; then
                : > "$FBRANCH_MARKER"
                exit 1
            fi
            cat
            """,
        )
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        result = self.run_script(
            "BPP-step.sh",
            ["--phylip_file", phylip, "--imap", imap, "--tree", tree,
             "--dstat", dstat, "--prefix", self.temp / "bpp_no_fbranch" / "round1"],
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertFalse(marker.exists(), "ancestral subset enumeration ran without --fbranch")

    def test_bpp_step_requires_prior_mass_after_nonuniform_phiprior(self):
        self.install_bpp_step_mocks()
        imap, tree, dstat, phylip = self.write_bpp_inputs()
        output_dir = self.temp / "bpp_prior"
        round1 = output_dir / "round1"

        first = self.run_script(
            "BPP-step.sh",
            [
                "--phylip_file", phylip, "--imap", imap, "--tree", tree,
                "--dstat", dstat, "--prefix", round1,
            ],
        )
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)

        ctl = output_dir / "round1.ctl"
        ctl.write_text(
            ctl.read_text(encoding="utf-8").replace("phiprior = 1 1", "phiprior = 2 2"),
            encoding="utf-8",
        )
        introgression = (output_dir / "round1.introgression").read_text(encoding="utf-8")
        labels = re.findall(r":\s*(Z\S+)\s*$", introgression, re.MULTILINE)
        mcmc = output_dir / "round1.mcmc.txt"
        phi_headers = [f"phi:{12 + index}<-{6 + index}:{label}" for index, label in enumerate(labels)]
        mcmc.write_text(
            "\t".join(["iter", *phi_headers]) + "\n" +
            "\t".join(["1", *("0" for _ in labels)]) + "\n",
            encoding="utf-8",
        )

        base_args = [
            "--phylip_file", phylip, "--imap", imap, "--tree", tree,
            "--dstat", dstat, "--prefix", output_dir / "round2",
            "--last_step", round1, "--skip_validation",
        ]
        missing = self.run_script("BPP-step.sh", base_args)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Supply --prior_mass", missing.stderr)

        supplied = self.run_script(
            "BPP-step.sh", [*base_args, "--prior_mass", "0.02"]
        )
        self.assertEqual(supplied.returncode, 0, supplied.stderr + supplied.stdout)
        self.assertIn("prior_mass=0.02", supplied.stderr)




    def test_record_versions_selects_bpp_version_line(self):
        self.environment.pop("CONDA_PREFIX", None)
        self.make_executable(
            "bpp",
            """
            #!/usr/bin/env bash
            echo "Detected CPU features: mmx sse sse2 avx avx2"
            echo "bpp v4.8.7_linux_x86_64, 63GB RAM, 32 cores"
            echo "https://github.com/bpp/bpp"
            """,
        )
        self.make_executable(
            "Dsuite",
            """
            #!/usr/bin/env bash
            echo "Program: Dsuite"
            echo "Version: 0.5 r58"
            """,
        )
        self.make_executable(
            "snp-sites",
            """
            #!/usr/bin/env bash
            echo "snp-sites 2.5.1"
            """,
        )
        self.make_executable("nw_prune", "#!/usr/bin/env bash\nexit 0\n")
        output = self.temp / "versions.tsv"
        result = self.run_script("scripts/record_versions.sh", [output])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        rows = {
            fields[0]: fields[1:]
            for fields in (
                line.split("\t")
                for line in output.read_text(encoding="utf-8").splitlines()[1:]
            )
        }
        self.assertEqual(
            rows["BPP"][0],
            "bpp v4.8.7_linux_x86_64, 63GB RAM, 32 cores",
        )

    def test_install_external_default_writes_release_pinned_metadata(self):
        self.install_external_installer_mocks()
        prefix = self.prepare_fake_conda_prefix()
        result = self.run_script("scripts/install_external.sh", [])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        metadata = dict(
            line.split("\t", 1)
            for line in (prefix / "opt" / "dbpp-external" / "install_metadata.tsv")
            .read_text(encoding="utf-8")
            .splitlines()[1:]
        )
        self.assertEqual(metadata["install_mode"], "release-pinned")
        self.assertEqual(metadata["bpp_version"], "4.8.7")
        self.assertEqual(
            metadata["dsuite_commit"],
            "a547f99599d763c1760548191ea3f62cc58e8ac3",
        )
        self.assertTrue((prefix / "bin" / "bpp").exists())
        self.assertTrue((prefix / "bin" / "Dsuite").exists())

    def test_install_external_latest_records_resolved_versions(self):
        self.install_external_installer_mocks()
        prefix = self.prepare_fake_conda_prefix()
        latest_commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        self.environment["FAKE_LATEST_DSUITE_COMMIT"] = latest_commit
        result = self.run_script("scripts/install_external.sh", ["--latest"])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("unpinned external dependencies", result.stderr)
        metadata = dict(
            line.split("\t", 1)
            for line in (prefix / "opt" / "dbpp-external" / "install_metadata.tsv")
            .read_text(encoding="utf-8")
            .splitlines()[1:]
        )
        self.assertEqual(metadata["install_mode"], "latest")
        self.assertEqual(metadata["bpp_version"], "9.9.9")
        self.assertEqual(metadata["dsuite_commit"], latest_commit)

    def test_install_external_help_documents_version_modes(self):
        result = self.run_script("scripts/install_external.sh", ["--help"])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("BPP 4.8.7", result.stdout)
        self.assertIn("--latest", result.stdout)
        self.assertIn("BPP_VERSION=<version>", result.stdout)
        self.assertIn("DSUITE_COMMIT=<commit>", result.stdout)

    def test_install_external_rejects_latest_with_explicit_override(self):
        previous = self.environment.get("BPP_VERSION")
        self.environment["BPP_VERSION"] = "4.9.0"
        try:
            result = self.run_script("scripts/install_external.sh", ["--latest"])
        finally:
            if previous is None:
                self.environment.pop("BPP_VERSION", None)
            else:
                self.environment["BPP_VERSION"] = previous
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)



if __name__ == "__main__":
    unittest.main()
